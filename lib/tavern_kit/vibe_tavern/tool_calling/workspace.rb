# frozen_string_literal: true

require "securerandom"

module TavernKit
  module VibeTavern
    module ToolCalling
      # In-memory editing workspace for tool-calling PoCs and eval harnesses.
      #
      # This is intentionally DB-free. The public shape is designed so it can be
      # swapped to an ActiveRecord-backed implementation later without changing
      # tool contracts.
      class Workspace
        attr_reader :id, :facts, :draft, :locks, :ui_state

        def initialize(id: nil, facts: nil, draft: nil, locks: nil, ui_state: nil)
          @id = (id || SecureRandom.uuid).to_s

          @facts = facts.is_a?(Hash) ? deep_dup(facts) : {}
          @draft = draft.is_a?(Hash) ? deep_dup(draft) : {}

          @locks = Array(locks).map(&:to_s)
          @ui_state = ui_state.is_a?(Hash) ? deep_dup(ui_state) : {}

          @facts_version = 0
          @draft_version = 0

          @fact_proposals = {} # proposal_id -> Array<{ "path"=>String, "value"=>Object, "reason"=>String }>
        end

        def facts_etag = "facts:#{@facts_version}"
        def draft_etag = "draft:#{@draft_version}"

        def snapshot(select: nil)
          full = {
            "facts" => deep_dup(@facts),
            "draft" => deep_dup(@draft),
            "locks" => { "paths" => @locks.dup },
            "ui_state" => deep_dup(@ui_state),
            "versions" => { "facts_etag" => facts_etag, "draft_etag" => draft_etag },
          }

          paths = Array(select).map(&:to_s).reject(&:empty?)
          return full if paths.empty?

          # Minimal projection helper: resolve a list of pointers against the full snapshot.
          paths.each_with_object({}) do |pointer, out|
            out[pointer] = read_pointer(full, pointer)
          rescue ArgumentError
            out[pointer] = nil
          end
        end

        def propose_facts!(proposals)
          proposal_id = SecureRandom.uuid
          items = Array(proposals).map do |p|
            p = p.is_a?(Hash) ? p : {}
            {
              "path" => p["path"].to_s,
              "value" => p.key?("value") ? p["value"] : nil,
              "reason" => p["reason"].to_s,
            }
          end

          @fact_proposals[proposal_id] = items
          proposal_id
        end

        def commit_facts!(proposal_id, user_confirmed:)
          raise ArgumentError, "user_confirmed is required" unless user_confirmed == true

          items = @fact_proposals.delete(proposal_id.to_s)
          raise ArgumentError, "proposal not found" unless items

          changed = []

          items.each do |item|
            path = item["path"].to_s
            next if path.empty?
            next unless path.start_with?("/facts/")
            next if locked_path?(path)

            write_pointer!(@facts, path.delete_prefix("/facts"), item["value"])
            changed << path
          end

          @facts_version += 1 unless changed.empty?

          {
            "facts_etag" => facts_etag,
            "committed" => changed.size,
            "changed_paths" => changed,
          }
        end

        def patch_draft!(ops, etag: nil)
          if etag && etag.to_s != draft_etag
            raise ArgumentError, "etag mismatch"
          end

          applied = 0
          before = deep_dup(@draft)

          begin
            Array(ops).each do |op|
              op = op.is_a?(Hash) ? op : {}

              action = op["op"].to_s
              path = op["path"].to_s
              value = op.key?("value") ? op["value"] : nil
              index = op["index"]

              raise ArgumentError, "path must start with /draft/" unless path.start_with?("/draft/")

              case action
              when "set"
                write_pointer!(@draft, path.delete_prefix("/draft"), value)
                applied += 1
              when "delete"
                delete_pointer!(@draft, path.delete_prefix("/draft"))
                applied += 1
              when "append"
                append_pointer!(@draft, path.delete_prefix("/draft"), value)
                applied += 1
              when "insert"
                insert_pointer!(@draft, path.delete_prefix("/draft"), index, value)
                applied += 1
              else
                raise ArgumentError, "unknown op: #{action.inspect}"
              end
            end
          rescue StandardError
            # Patch operations are expected to be atomic. Even if we validate
            # inputs up front, nested pointer writes can still fail (bad index,
            # unexpected structure, etc.). Roll back to keep state consistent.
            @draft = before
            raise
          end

          @draft_version += 1 if applied.positive?

          {
            "draft_etag" => draft_etag,
            "applied" => applied,
          }
        end

        def locked_path?(path)
          path = path.to_s
          @locks.any? { |prefix| path.start_with?(prefix) }
        end

        private

        # Very small JSON Pointer helpers (enough for PoC).
        def read_pointer(doc, pointer)
          raise ArgumentError, "pointer must start with /" unless pointer.to_s.start_with?("/")

          tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
          tokens.reduce(doc) do |cur, tok|
            case cur
            when Hash
              cur.fetch(tok)
            when Array
              cur.fetch(Integer(tok))
            else
              raise ArgumentError, "cannot descend into #{cur.class}"
            end
          end
        end

        def write_pointer!(doc, pointer, value)
          pointer = pointer.to_s
          return doc.replace(value) if pointer.empty? || pointer == "/"

          raise ArgumentError, "pointer must start with /" unless pointer.start_with?("/")

          tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
          last = tokens.pop
          parent = tokens.reduce(doc) { |cur, tok| descend_write!(cur, tok) }

          case parent
          when Hash
            parent[last] = value
          when Array
            parent[Integer(last)] = value
          else
            raise ArgumentError, "cannot write into #{parent.class}"
          end
        end

        def delete_pointer!(doc, pointer)
          raise ArgumentError, "pointer must start with /" unless pointer.to_s.start_with?("/")

          tokens = pointer.split("/").drop(1).map { |t| unescape_pointer_token(t) }
          last = tokens.pop
          parent = tokens.reduce(doc) { |cur, tok| descend_write!(cur, tok) }

          case parent
          when Hash
            parent.delete(last)
          when Array
            parent.delete_at(Integer(last))
          else
            raise ArgumentError, "cannot delete from #{parent.class}"
          end
        end

        def append_pointer!(doc, pointer, value)
          arr = read_pointer(doc, pointer)
          raise ArgumentError, "target is not an Array" unless arr.is_a?(Array)

          arr << value
        rescue KeyError
          # Create the array if it doesn't exist.
          write_pointer!(doc, pointer, [value])
        end

        def insert_pointer!(doc, pointer, index, value)
          arr = read_pointer(doc, pointer)
          raise ArgumentError, "target is not an Array" unless arr.is_a?(Array)

          i = Integer(index)
          arr.insert(i, value)
        rescue KeyError
          write_pointer!(doc, pointer, [value])
        end

        def descend_write!(cur, tok)
          case cur
          when Hash
            cur[tok] ||= {}
            cur[tok]
          when Array
            idx = Integer(tok)
            cur[idx] ||= {}
            cur[idx]
          else
            raise ArgumentError, "cannot descend into #{cur.class}"
          end
        end

        def unescape_pointer_token(token)
          token.to_s.gsub("~1", "/").gsub("~0", "~")
        end

        def deep_dup(obj)
          Marshal.load(Marshal.dump(obj))
        end
      end
    end
  end
end
