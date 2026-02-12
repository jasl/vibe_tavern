# frozen_string_literal: true

require_relative "../../tools/skills/store"
require_relative "../support/envelope"
require_relative "../support/utf8"

module TavernKit
  module VibeTavern
    module ToolCalling
      module Executors
        class SkillsExecutor
          DEFAULT_MAX_BYTES = 200_000

          def initialize(store:, max_bytes: DEFAULT_MAX_BYTES)
            raise ArgumentError, "store is required" unless store.is_a?(TavernKit::VibeTavern::Tools::Skills::Store)

            @store = store
            @max_bytes = Integer(max_bytes)
            raise ArgumentError, "max_bytes must be positive" if @max_bytes <= 0
          end

          def call(name:, args:, tool_call_id: nil)
            tool_name = name.to_s
            args = args.is_a?(Hash) ? args : {}

            case tool_name
            when "skills_list"
              skills = @store.list_skills.map { |m| { name: m.name, description: m.description } }
              ok_envelope(tool_name, skills: skills)
            when "skills_load"
              skill_name = fetch_arg(args, "name")
              raise ArgumentError, "name is required" if skill_name.empty?

              skill = @store.load_skill(name: skill_name)
              body = normalize_utf8(skill.body_markdown.to_s)

              warnings = []
              if body.bytesize > @max_bytes
                body = body.byteslice(0, @max_bytes).to_s
                body = normalize_utf8(body)
                warnings << { code: "CONTENT_TRUNCATED", message: "SKILL.md body exceeded size limit and was truncated" }
              end

              files =
                skill.files_index.values.flatten.sort

              envelope = ok_envelope(tool_name, name: skill.meta.name, description: skill.meta.description, body_markdown: body, files: files)
              envelope[:warnings] = warnings if warnings.any?
              envelope
            when "skills_read_file"
              skill_name = fetch_arg(args, "name")
              raise ArgumentError, "name is required" if skill_name.empty?

              rel_path = fetch_arg(args, "path")
              raise ArgumentError, "path is required" if rel_path.empty?

              content = @store.read_skill_file(name: skill_name, rel_path: rel_path, max_bytes: @max_bytes)
              ok_envelope(tool_name, path: rel_path.to_s, content: content)
            when "skills_run_script"
              error_envelope(tool_name, code: "NOT_IMPLEMENTED", message: "skills_run_script is not implemented")
            else
              error_envelope(tool_name, code: "TOOL_NOT_IMPLEMENTED", message: "Tool not implemented: #{tool_name}")
            end
          rescue ArgumentError => e
            map_argument_error(tool_name, e)
          rescue StandardError => e
            error_envelope(tool_name, code: "INTERNAL_ERROR", message: "#{e.class}: #{e.message}")
          end

          private

          def fetch_arg(args, key)
            if args.key?(key)
              args.fetch(key).to_s.strip
            elsif args.key?(key.to_sym)
              args.fetch(key.to_sym).to_s.strip
            else
              ""
            end
          end

          def map_argument_error(tool_name, error)
            msg = error.message.to_s

            if msg.start_with?("Unknown skill:")
              return error_envelope(tool_name, code: "SKILL_NOT_FOUND", message: msg)
            end

            if msg.start_with?("Invalid skill file path:")
              return error_envelope(tool_name, code: "INVALID_PATH", message: msg)
            end

            if msg.start_with?("Skill file not found:")
              return error_envelope(tool_name, code: "FILE_NOT_FOUND", message: msg)
            end

            if msg.start_with?("Skill file too large:")
              return error_envelope(tool_name, code: "FILE_TOO_LARGE", message: msg)
            end

            error_envelope(tool_name, code: "ARGUMENT_ERROR", message: msg)
          end

          def ok_envelope(tool_name, data = {})
            TavernKit::VibeTavern::ToolCalling::Support::Envelope.ok_envelope(tool_name, data)
          end

          def error_envelope(tool_name, code:, message:)
            TavernKit::VibeTavern::ToolCalling::Support::Envelope.error_envelope(tool_name, code: code, message: message)
          end

          def normalize_utf8(value)
            TavernKit::VibeTavern::ToolCalling::Support::Utf8.normalize_utf8(value)
          end
        end
      end
    end
  end
end
