# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Lore
      class Engine < TavernKit::Lore::Engine::Base
        private

        # Pure refactor: extracted from `risu_ai/lore/engine.rb`.
        def internal_keep_key(entry)
          suffix = entry.id.to_s
          if suffix.empty?
            suffix = TavernKit::RisuAI::Utils.pick_hash_rand(5555, entry.content).to_s
          end
          "__internal_ka_#{suffix}"
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb`.
        def internal_dont_key(entry)
          suffix = entry.id.to_s
          if suffix.empty?
            suffix = TavernKit::RisuAI::Utils.pick_hash_rand(5555, entry.content).to_s
          end
          "__internal_da_#{suffix}"
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb`.
        def build_active(entry, chat_length:, greeting_index:, global_scan_depth:, global_full_word:, variables:)
          h = entry.to_h
          ext = TavernKit::Utils::HashAccessor.wrap(h.fetch("extensions", {}))

          mode = ext.fetch(:mode, default: nil)
          return nil if mode.to_s == "folder"

          activated = entry.enabled?
          position = ""
          depth = 0
          scan_depth = global_scan_depth
          role = :system
          order = entry.insertion_order.to_i
          priority = order
          force_state = :none
          search_queries = []
          full_word = global_full_word
          dont_search_when_recursive = false
          recursive_override = nil
          keep_activate_after_match = false
          dont_activate_after_match = false
          inject = nil

          parsed = TavernKit::RisuAI::Lore::DecoratorParser.parse(entry.content) do |name, args|
            case name
            when "end"
              position = "depth"
              depth = 0
              nil
            when "activate_only_after"
              int = safe_int(args[0])
              return false if int.nil?

              activated = false if chat_length < int
              nil
            when "activate_only_every"
              int = safe_int(args[0])
              return false if int.nil?

              activated = false if int.positive? && (chat_length % int) != 0
              nil
            when "keep_activate_after_match"
              if variables.get(internal_keep_key(entry), scope: :global).to_s == "true"
                force_state = :activate
              else
                keep_activate_after_match = true
              end
              false
            when "dont_activate_after_match"
              if variables.get(internal_dont_key(entry), scope: :global).to_s == "true"
                force_state = :deactivate
              else
                dont_activate_after_match = true
              end
              false
            when "depth"
              int = safe_int(args[0])
              return false if int.nil?

              depth = int
              position = "depth"
              nil
            when "reverse_depth"
              int = safe_int(args[0])
              return false if int.nil?

              depth = int
              position = "reverse_depth"
              nil
            when "instruct_depth", "reverse_instruct_depth", "instruct_scan_depth"
              false
            when "role"
              v = args[0].to_s
              return false unless %w[user assistant system].include?(v)

              role = v.to_sym
              nil
            when "scan_depth"
              int = safe_int(args[0])
              return false if int.nil?

              scan_depth = int
              nil
            when "is_greeting"
              int = safe_int(args[0])
              return false if int.nil?

              # Upstream uses (fmIndex + 1) compared to int.
              if greeting_index.nil? || (greeting_index.to_i + 1) != int
                activated = false
              end
              nil
            when "position"
              v = args[0].to_s
              return false unless v.start_with?("pt_") || %w[after_desc before_desc personality scenario].include?(v)

              position = v
              nil
            when "inject_lore"
              inject ||= Inject.new(operation: :append, location: "", param: "", lore: true)
              inject = inject.with(location: args.join(" "), lore: true)
              nil
            when "inject_at"
              inject ||= Inject.new(operation: :append, location: "", param: "", lore: false)
              inject = inject.with(location: args.join(" "), lore: false)
              nil
            when "inject_replace"
              inject ||= Inject.new(operation: :replace, location: "", param: "", lore: false)
              inject = inject.with(operation: :replace, param: args.join(" "))
              nil
            when "inject_prepend"
              inject ||= Inject.new(operation: :prepend, location: "", param: "", lore: false)
              inject = inject.with(operation: :prepend, param: args.join(" "))
              nil
            when "ignore_on_max_context"
              priority = -1000
              nil
            when "additional_keys"
              search_queries << { keys: args, negative: false }
              nil
            when "exclude_keys"
              search_queries << { keys: args, negative: true }
              nil
            when "exclude_keys_all"
              search_queries << { keys: args, negative: true, all: true }
              nil
            when "match_full_word"
              full_word = true
              nil
            when "match_partial_word"
              full_word = false
              nil
            when "activate"
              force_state = :activate
              nil
            when "dont_activate"
              force_state = :deactivate
              nil
            when "probability"
              pct = safe_int(args[0])
              return false if pct.nil?

              activated = false if (@rng.rand * 100) > pct
              nil
            when "priority"
              int = safe_int(args[0])
              return false if int.nil?

              priority = int
              nil
            when "unrecursive"
              recursive_override = false
              nil
            when "recursive"
              recursive_override = true
              nil
            when "no_recursive_search"
              dont_search_when_recursive = true
              nil
            else
              false
            end
          end

          return nil unless activated

          cleaned = parsed.content.to_s
          tokens = @token_estimator.estimate(cleaned)

          Active.new(
            entry: entry,
            content: cleaned,
            depth: depth,
            position: position,
            role: role,
            order: order,
            priority: priority,
            tokens: tokens.to_i,
            source: entry.comment.to_s.empty? ? (entry.name.to_s.empty? ? "lorebook" : entry.name.to_s) : entry.comment.to_s,
            inject: inject,
            scan_depth: scan_depth.to_i,
            full_word_match: full_word == true,
            dont_search_when_recursive: dont_search_when_recursive == true,
            recursive_override: recursive_override,
            force_state: force_state,
            keep_activate_after_match: keep_activate_after_match == true,
            dont_activate_after_match: dont_activate_after_match == true,
            search_queries: search_queries,
          )
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb`.
        def safe_int(value)
          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
