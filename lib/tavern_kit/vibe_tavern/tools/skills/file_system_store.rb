# frozen_string_literal: true

require "pathname"

require_relative "frontmatter"
require_relative "skill_metadata"
require_relative "skill"
require_relative "store"

module TavernKit
  module VibeTavern
    module Tools
      module Skills
        class FileSystemStore < Store
          DEFAULT_MAX_BYTES = 200_000
          SKILL_MD_FRONTMATTER_MAX_BYTES = 50_000
          ALLOWED_TOP_DIRS = %w[scripts references assets].freeze
          REL_PATH_PATTERN = /\A(?:scripts|references|assets)\/[^\/]+\z/.freeze

          def initialize(dirs:, strict: true)
            @strict = strict == true
            @dirs = normalize_dirs(dirs)

            validate_dirs!
          end

          # Returns Array<SkillMetadata>.
          #
          # This is metadata-only: it reads SKILL.md frontmatter but does not load
          # the full body (progressive disclosure).
          def list_skills
            seen = {}
            metas = []

            each_skill_dir do |skill_dir|
              skill_md_path = File.join(skill_dir, "SKILL.md")
              next unless File.file?(skill_md_path)

              content = read_skill_md_for_frontmatter(skill_md_path)
              frontmatter, =
                Frontmatter.parse(
                  content,
                  expected_name: File.basename(skill_dir),
                  path: skill_md_path,
                  strict: @strict,
                )
              next if frontmatter.nil?

              meta =
                SkillMetadata.new(
                  name: frontmatter.fetch(:name),
                  description: frontmatter.fetch(:description),
                  location: File.expand_path(skill_dir),
                  license: frontmatter.fetch(:license, nil),
                  compatibility: frontmatter.fetch(:compatibility, nil),
                  metadata: frontmatter.fetch(:metadata, {}),
                  allowed_tools: frontmatter.fetch(:allowed_tools, nil),
                )

              if seen.key?(meta.name)
                raise ArgumentError, "duplicate skill name: #{meta.name}" if @strict

                next
              end

              seen[meta.name] = true
              metas << meta
            end

            metas.sort_by!(&:name)
            metas
          end

          def load_skill(name:)
            meta = find_skill_metadata!(name.to_s)
            skill_dir = meta.location
            skill_md_path = File.join(skill_dir, "SKILL.md")
            raise ArgumentError, "SKILL.md not found for skill: #{meta.name}" unless File.file?(skill_md_path)

            content = File.read(skill_md_path)
            frontmatter, body_markdown =
              Frontmatter.parse(
                content,
                expected_name: File.basename(skill_dir),
                path: skill_md_path,
                strict: true,
              )

            loaded_meta =
              SkillMetadata.new(
                name: frontmatter.fetch(:name),
                description: frontmatter.fetch(:description),
                location: File.expand_path(skill_dir),
                license: frontmatter.fetch(:license, nil),
                compatibility: frontmatter.fetch(:compatibility, nil),
                metadata: frontmatter.fetch(:metadata, {}),
                allowed_tools: frontmatter.fetch(:allowed_tools, nil),
              )

            Skill.new(
              meta: loaded_meta,
              body_markdown: body_markdown.to_s,
              files_index: index_files(skill_dir),
            )
          end

          def read_skill_file(name:, rel_path:, max_bytes: DEFAULT_MAX_BYTES)
            meta = find_skill_metadata!(name.to_s)

            normalized = normalize_rel_path(rel_path)
            abs_path = safe_join(meta.location, normalized)

            unless File.file?(abs_path)
              raise ArgumentError, "Skill file not found: #{normalized}"
            end

            ensure_realpath_within_skill_dir!(skill_dir: meta.location, abs_path: abs_path, rel_path: normalized)

            content = read_file_limited(abs_path, max_bytes: max_bytes.to_i, label: normalized)
            normalize_utf8(content)
          end

          private

          def normalize_dirs(value)
            Array(value)
              .map { |v| v.to_s.strip }
              .reject(&:empty?)
              .map { |v| File.expand_path(v) }
              .uniq
          end

          def validate_dirs!
            @dirs =
              @dirs.select do |dir|
                ok = File.directory?(dir)
                next ok if ok || !@strict

                raise ArgumentError, "skills dir does not exist: #{dir}"
              end
          end

          def each_skill_dir(&block)
            @dirs.each do |root|
              next unless File.directory?(root)

              Dir.children(root).sort.each do |entry|
                next if entry.start_with?(".")

                skill_dir = File.join(root, entry)
                next unless File.directory?(skill_dir)

                block.call(skill_dir)
              end
            end
          end

          def read_skill_md_for_frontmatter(path)
            max_bytes = SKILL_MD_FRONTMATTER_MAX_BYTES
            raw =
              File.open(path, "rb") do |io|
                io.read(max_bytes + 1)
              end
            raw = raw.to_s

            truncated = raw.bytesize > max_bytes
            data = truncated ? raw.byteslice(0, max_bytes).to_s : raw

            lines = data.lines
            closing_index = nil
            lines.each_with_index do |line, idx|
              next if idx == 0

              if line.strip == "---"
                closing_index = idx
                break
              end
            end

            if closing_index
              return lines[0..closing_index].join
            end

            if truncated && @strict
              raise ArgumentError, "SKILL.md frontmatter exceeds #{max_bytes} bytes: #{path}"
            end

            data
          rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError => e
            raise ArgumentError, "Failed to read SKILL.md: #{path} (#{e.class}: #{e.message})" if @strict

            ""
          end

          def find_skill_metadata!(name)
            name = name.to_s
            meta = list_skills.find { |m| m.name == name }
            raise ArgumentError, "Unknown skill: #{name}" unless meta

            meta
          end

          def index_files(skill_dir)
            {
              scripts: index_top_level_files(skill_dir, "scripts"),
              references: index_top_level_files(skill_dir, "references"),
              assets: index_top_level_files(skill_dir, "assets"),
            }
          end

          def index_top_level_files(skill_dir, subdir)
            dir = File.join(skill_dir, subdir)
            return [] unless File.directory?(dir)

            base_real = File.realpath(skill_dir.to_s)
            dir_real = File.realpath(dir.to_s)
            return [] unless dir_real.start_with?(base_real + File::SEPARATOR)

            Dir.children(dir).sort.filter_map do |entry|
              next if entry.start_with?(".")

              abs = File.join(dir, entry)
              next unless File.file?(abs)

              "#{subdir}/#{entry}"
            end
          rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError
            []
          end

          def normalize_rel_path(value)
            raw = value.to_s
            normalized = raw.tr("\\", "/").strip
            raise ArgumentError, "Invalid skill file path: #{raw}" if normalized.empty?

            if absolute_path?(normalized)
              raise ArgumentError, "Invalid skill file path: #{raw}"
            end

            unless REL_PATH_PATTERN.match?(normalized)
              raise ArgumentError, "Invalid skill file path: #{raw}"
            end

            segments = normalized.split("/")
            if segments.any? { |s| s == "." || s == ".." }
              raise ArgumentError, "Invalid skill file path: #{raw}"
            end

            top = segments.first
            raise ArgumentError, "Invalid skill file path: #{raw}" unless ALLOWED_TOP_DIRS.include?(top)

            normalized
          end

          def absolute_path?(value)
            return true if value.start_with?("/", "\\")
            return true if value.match?(/\A[a-zA-Z]:[\/\\]/)

            Pathname.new(value).absolute?
          end

          def safe_join(base_dir, rel_path)
            base = File.expand_path(base_dir.to_s)
            target = File.expand_path(File.join(base, rel_path))

            unless target.start_with?(base + File::SEPARATOR) || target == base
              raise ArgumentError, "Invalid skill file path: #{rel_path}"
            end

            target
          end

          def ensure_realpath_within_skill_dir!(skill_dir:, abs_path:, rel_path:)
            base = File.realpath(skill_dir.to_s)
            target = File.realpath(abs_path.to_s)

            unless target.start_with?(base + File::SEPARATOR)
              raise ArgumentError, "Invalid skill file path: #{rel_path}"
            end

            true
          rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError
            raise ArgumentError, "Invalid skill file path: #{rel_path}"
          end

          def read_file_limited(path, max_bytes:, label:)
            max_bytes = Integer(max_bytes)
            raise ArgumentError, "max_bytes must be positive" if max_bytes <= 0

            data =
              File.open(path, "rb") do |io|
                io.read(max_bytes + 1)
              end

            if data && data.bytesize > max_bytes
              raise ArgumentError, "Skill file too large: #{label}"
            end

            data.to_s
          end

          def normalize_utf8(value)
            str = value.to_s
            str = str.dup.force_encoding(Encoding::UTF_8)
            return str if str.valid_encoding?

            str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
          rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
            str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
          end
        end
      end
    end
  end
end
