# frozen_string_literal: true

module AgentCore
  module Resources
    module Skills
      # Builds native tools for interacting with a Skills::Store.
      #
      # These tools are designed for tool calling and are fully auditable
      # (they flow through the same tool policy + trace hooks as other tools).
      module Tools
        DEFAULT_MAX_BODY_BYTES = 200_000
        DEFAULT_MAX_FILE_BYTES = 200_000
        DEFAULT_TOOL_NAME_PREFIX = "skills."

        module_function

        def build(store:, max_body_bytes: DEFAULT_MAX_BODY_BYTES, max_file_bytes: DEFAULT_MAX_FILE_BYTES, tool_name_prefix: DEFAULT_TOOL_NAME_PREFIX)
          unless store.respond_to?(:list_skills) && store.respond_to?(:load_skill) && store.respond_to?(:read_skill_file_bytes)
            raise ArgumentError, "store must implement Skills::Store"
          end

          max_body_bytes = Integer(max_body_bytes)
          max_file_bytes = Integer(max_file_bytes)
          raise ArgumentError, "max_body_bytes must be positive" if max_body_bytes <= 0
          raise ArgumentError, "max_file_bytes must be positive" if max_file_bytes <= 0

          prefix = tool_name_prefix.to_s
          prefix = "#{prefix}." unless prefix.empty? || prefix.end_with?(".")

          [
            build_list_tool(store: store, prefix: prefix, max_bytes: max_body_bytes),
            build_load_tool(store: store, prefix: prefix, max_bytes: max_body_bytes),
            build_read_file_tool(store: store, prefix: prefix, max_bytes: max_file_bytes),
          ]
        end

        def build_list_tool(store:, prefix:, max_bytes:)
          Resources::Tools::Tool.new(
            name: "#{prefix}list",
            description: "List available skills (metadata only).",
            metadata: { source: :skills },
            parameters: {
              type: "object",
              additionalProperties: false,
            },
          ) do |_args, **|
            require "json"

            items =
              store.list_skills.map do |meta|
                {
                  "name" => meta.name,
                  "description" => meta.description,
                  "license" => meta.license,
                  "compatibility" => meta.compatibility,
                  "allowed_tools" => meta.allowed_tools,
                  "metadata" => meta.metadata,
                }.compact
              end

            payload = { "skills" => items, "truncated" => false }
            json = JSON.generate(payload)

            if json.bytesize > max_bytes
              limited = []
              items.each do |item|
                limited << item
                json = JSON.generate({ "skills" => limited, "truncated" => true })
                break if json.bytesize > max_bytes
              end

              limited.pop if json.bytesize > max_bytes && limited.any?
              payload = { "skills" => limited, "truncated" => true }
              json = JSON.generate(payload)
            end

            Resources::Tools::ToolResult.success(text: json)
          rescue StandardError => e
            Resources::Tools::ToolResult.error(text: "skills.list failed: #{e.message}")
          end
        end
        private_class_method :build_list_tool

        def build_load_tool(store:, prefix:, max_bytes:)
          Resources::Tools::Tool.new(
            name: "#{prefix}load",
            description: "Load a skill by name (body markdown + files index).",
            metadata: { source: :skills },
            parameters: {
              type: "object",
              additionalProperties: false,
              properties: {
                name: { type: "string" },
              },
              required: ["name"],
            },
          ) do |args, **|
            require "json"

            name = args.fetch("name").to_s
            skill = store.load_skill(name: name, max_bytes: max_bytes)

            payload = {
              "meta" => {
                "name" => skill.meta.name,
                "description" => skill.meta.description,
                "license" => skill.meta.license,
                "compatibility" => skill.meta.compatibility,
                "allowed_tools" => skill.meta.allowed_tools,
                "metadata" => skill.meta.metadata,
              }.compact,
              "body_markdown" => skill.body_markdown,
              "body_truncated" => skill.body_truncated,
              "files_index" => skill.files_index.transform_values { |v| Array(v) },
            }

            json = JSON.generate(payload)
            if json.bytesize > max_bytes
              body = Utils.truncate_utf8_bytes(skill.body_markdown, max_bytes: [max_bytes - 1_000, 0].max)
              payload["body_markdown"] = body
              payload["body_truncated"] = true
              json = JSON.generate(payload)
            end

            Resources::Tools::ToolResult.success(text: json)
          rescue KeyError => e
            Resources::Tools::ToolResult.error(text: "skills.load missing argument: #{e.message}")
          rescue StandardError => e
            Resources::Tools::ToolResult.error(text: "skills.load failed: #{e.message}")
          end
        end
        private_class_method :build_load_tool

        def build_read_file_tool(store:, prefix:, max_bytes:)
          Resources::Tools::Tool.new(
            name: "#{prefix}read_file",
            description: "Read a file from within a skill directory (scripts/references/assets).",
            metadata: { source: :skills },
            parameters: {
              type: "object",
              additionalProperties: false,
              properties: {
                name: { type: "string" },
                rel_path: { type: "string" },
              },
              required: ["name", "rel_path"],
            },
          ) do |args, **|
            name = args.fetch("name").to_s
            rel_path = args.fetch("rel_path").to_s

            bytes = store.read_skill_file_bytes(name: name, rel_path: rel_path, max_bytes: max_bytes)

            text = bytes.dup.force_encoding(Encoding::UTF_8)
            if text.valid_encoding? && !text.include?("\u0000")
              Resources::Tools::ToolResult.success(text: text)
            else
              require "base64"

              media_type = Utils.infer_mime_type(rel_path) || "application/octet-stream"
              base64 = Base64.strict_encode64(bytes)

              block =
                if media_type.start_with?("image/")
                  { type: :image, source_type: :base64, media_type: media_type, data: base64 }
                elsif media_type.start_with?("audio/")
                  { type: :audio, source_type: :base64, media_type: media_type, data: base64 }
                else
                  { type: :document, source_type: :base64, media_type: media_type, data: base64, filename: File.basename(rel_path) }
                end

              Resources::Tools::ToolResult.with_content(
                [block],
                metadata: { bytes: bytes.bytesize, media_type: media_type, filename: File.basename(rel_path) }
              )
            end
          rescue KeyError => e
            Resources::Tools::ToolResult.error(text: "skills.read_file missing argument: #{e.message}")
          rescue StandardError => e
            Resources::Tools::ToolResult.error(text: "skills.read_file failed: #{e.message}")
          end
        end
        private_class_method :build_read_file_tool
      end
    end
  end
end
