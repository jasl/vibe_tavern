# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      module Sources
        class FileSet < Source::Base
          DEFAULT_SECTION_HEADER = "Project Context"

          def initialize(
            files:,
            order: 0,
            prompt_modes: PROMPT_MODES,
            root_key: nil,
            total_max_bytes: nil,
            marker: Truncation::DEFAULT_MARKER,
            section_header: DEFAULT_SECTION_HEADER,
            substitute_variables: false,
            include_missing: true
          )
            @files = Array(files)
            @order = Integer(order || 0, exception: false) || 0
            @prompt_modes = Array(prompt_modes).map { |m| m.to_sym }
            @root_key = root_key&.to_sym
            @total_max_bytes = total_max_bytes
            @marker = marker.to_s
            @section_header = section_header.to_s.strip
            @section_header = DEFAULT_SECTION_HEADER if @section_header.empty?
            @substitute_variables = substitute_variables == true
            @include_missing = include_missing == true
          end

          def items(agent:, user_message:, execution_context:, prompt_mode:)
            root = resolve_root_dir(execution_context)
            selected_files = filter_files_for_mode(prompt_mode)

            body = +"# #{@section_header}\n"

            selected_files.each do |spec|
              rendered = render_file(spec, root: root)
              next if rendered.nil?

              body << "\n" unless body.end_with?("\n\n")
              body << rendered
              body << "\n" unless body.end_with?("\n")
            end

            if @total_max_bytes
              body = Truncation.head_marker_tail(body, max_bytes: @total_max_bytes, marker: @marker)
            end

            item =
              Item.new(
                target: :system_section,
                content: body,
                order: @order,
                prompt_modes: @prompt_modes,
                substitute_variables: @substitute_variables,
              )

            [item]
          rescue StandardError
            []
          end

          private

          def resolve_root_dir(execution_context)
            attrs = execution_context.attributes

            root =
              if @root_key
                attrs[@root_key]
              else
                attrs[:workspace_dir] || attrs[:cwd]
              end

            root = Dir.pwd if root.to_s.strip.empty?
            File.expand_path(root.to_s)
          rescue StandardError
            Dir.pwd
          end

          def filter_files_for_mode(prompt_mode)
            mode = prompt_mode.to_sym
            @files.select do |spec|
              h = spec.is_a?(Hash) ? AgentCore::Utils.symbolize_keys(spec) : {}
              modes = Array(h.fetch(:prompt_modes, PROMPT_MODES)).map { |m| m.to_sym }
              modes.include?(mode)
            end
          rescue StandardError
            @files
          end

          def render_file(spec, root:)
            h = spec.is_a?(Hash) ? AgentCore::Utils.symbolize_keys(spec) : {}
            rel = h.fetch(:path).to_s
            return nil if rel.strip.empty?

            title = h.fetch(:title, rel).to_s.strip
            title = rel if title.empty?

            path = safe_join(root, rel)

            max_bytes = h[:max_bytes]
            max_bytes = Integer(max_bytes, exception: false) if max_bytes

            content =
              if path && File.file?(path)
                Truncation.normalize_utf8(File.binread(path))
              elsif @include_missing
                "[MISSING] #{rel}"
              end

            return nil if content.nil?

            if max_bytes && max_bytes.positive?
              content = Truncation.head_marker_tail(content, max_bytes: max_bytes, marker: @marker)
            end

            "## #{title}\n#{content}"
          rescue StandardError
            nil
          end

          def safe_join(root, rel)
            root = File.expand_path(root.to_s)
            path = File.expand_path(rel.to_s, root)
            return root if path == root
            return path if path.start_with?(root + File::SEPARATOR)

            nil
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
