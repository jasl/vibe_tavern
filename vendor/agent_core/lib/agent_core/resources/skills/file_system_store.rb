# frozen_string_literal: true

require "pathname"

module AgentCore
  module Resources
    module Skills
      # Filesystem-backed skill store.
      #
      # Scans one or more directories for skill directories (each containing
      # a SKILL.md with frontmatter). Supports progressive disclosure:
      # list_skills reads frontmatter only, load_skill reads the full body.
      #
      # Security: validates all paths with realpath to prevent symlink escapes.
      class FileSystemStore < Store
        DEFAULT_MAX_BYTES = 200_000
        SKILL_MD_FRONTMATTER_MAX_BYTES = 50_000
        ALLOWED_TOP_DIRS = %w[scripts references assets].freeze
        REL_PATH_PATTERN = /\A(?:scripts|references|assets)\/[^\/]+\z/.freeze
        SKILL_MD_FILENAMES = %w[SKILL.md skill.md].freeze

        # @param dirs [Array<String>, String] Directories to scan for skills
        # @param strict [Boolean] Whether to raise on errors or skip silently
        def initialize(dirs:, strict: true)
          @strict = strict == true
          @dirs = normalize_dirs(dirs)

          validate_dirs!
        end

        # Returns Array<SkillMetadata> (metadata-only, progressive disclosure).
        def list_skills
          seen = {}
          metas = []

          each_skill_dir do |skill_dir, skill_real|
            skill_md_path = find_skill_md(skill_dir)
            next unless skill_md_path

            skill_md_real =
              begin
                ensure_realpath_within_dir!(
                  base_dir: skill_real,
                  abs_path: skill_md_path,
                  label: File.basename(skill_md_path),
                )
              rescue ArgumentError
                raise if @strict

                next
              end
            content = read_skill_md_for_frontmatter(skill_md_real)
            frontmatter, =
              Frontmatter.parse(
                content,
                expected_name: File.basename(skill_dir),
                path: skill_md_real,
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

        # Load a skill by name (full body + file index).
        def load_skill(name:, max_bytes: nil)
          meta = find_skill_metadata!(name.to_s)
          skill_dir = meta.location
          skill_md_path = find_skill_md(skill_dir)
          unless skill_md_path
            raise ArgumentError, "SKILL.md not found for skill: #{meta.name}"
          end

          max_bytes = max_bytes.nil? ? DEFAULT_MAX_BYTES : Integer(max_bytes)
          raise ArgumentError, "max_bytes must be positive" if max_bytes <= 0

          skill_real = File.realpath(skill_dir.to_s)
          skill_md_real =
            ensure_realpath_within_dir!(
              base_dir: skill_real,
              abs_path: skill_md_path,
              label: File.basename(skill_md_path),
            )

          content, truncated = read_file_prefix(skill_md_real, max_bytes: max_bytes, label: "SKILL.md")
          frontmatter, body_markdown =
            Frontmatter.parse(
              content,
              expected_name: File.basename(skill_dir),
              path: skill_md_real,
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
            body_truncated: truncated,
            files_index: index_files(skill_dir),
          )
        end

        # Read a specific file from within a skill directory.
        def read_skill_file(name:, rel_path:, max_bytes: DEFAULT_MAX_BYTES)
          raw = read_skill_file_bytes(name: name, rel_path: rel_path, max_bytes: max_bytes)
          normalize_utf8(raw)
        end

        # Read raw bytes for a file from within a skill directory.
        def read_skill_file_bytes(name:, rel_path:, max_bytes: DEFAULT_MAX_BYTES)
          meta = find_skill_metadata!(name.to_s)

          normalized = normalize_rel_path(rel_path)
          abs_path = safe_join(meta.location, normalized)

          unless File.file?(abs_path)
            raise ArgumentError, "Skill file not found: #{normalized}"
          end

          ensure_realpath_within_skill_dir!(skill_dir: meta.location, abs_path: abs_path, rel_path: normalized)

          content = read_file_limited(abs_path, max_bytes: max_bytes.to_i, label: normalized)
          content.to_s.dup.force_encoding(Encoding::BINARY)
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

            base_real =
              begin
                File.realpath(root.to_s)
              rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError => e
                raise ArgumentError, "Failed to scan skills dir: #{root} (#{e.class}: #{e.message})" if @strict

                next
              end

            entries =
              begin
                Dir.children(root).sort
              rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError => e
                raise ArgumentError, "Failed to scan skills dir: #{root} (#{e.class}: #{e.message})" if @strict

                next
              end

            entries.each do |entry|
              next if entry.start_with?(".")

              skill_dir = File.join(root, entry)
              next unless File.directory?(skill_dir)

              skill_real =
                begin
                  File.realpath(skill_dir.to_s)
                rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError => e
                  raise ArgumentError, "Failed to read skill directory: #{skill_dir} (#{e.class}: #{e.message})" if @strict

                  next
                end
              unless within_dir?(base_real, skill_real)
                raise ArgumentError, "Skill directory escapes skills root: #{skill_dir}" if @strict

                next
              end

              block.call(skill_dir, skill_real)
            end
          end
        end

        def ensure_realpath_within_dir!(base_dir:, abs_path:, label:)
          base = File.realpath(base_dir.to_s)
          target = File.realpath(abs_path.to_s)

          unless within_dir?(base, target)
            raise ArgumentError, "Invalid skill #{label} path"
          end

          target
        rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError
          raise ArgumentError, "Invalid skill #{label} path"
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

        def find_skill_md(skill_dir)
          SKILL_MD_FILENAMES.each do |name|
            path = File.join(skill_dir, name)
            return path if File.file?(path)
          end

          nil
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
          return [] unless within_dir?(base_real, dir_real)

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

          unless within_dir?(base, target)
            raise ArgumentError, "Invalid skill file path: #{rel_path}"
          end

          target
        end

        def ensure_realpath_within_skill_dir!(skill_dir:, abs_path:, rel_path:)
          base = File.realpath(skill_dir.to_s)
          target = File.realpath(abs_path.to_s)

          unless within_dir?(base, target)
            raise ArgumentError, "Invalid skill file path: #{rel_path}"
          end

          true
        rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError
          raise ArgumentError, "Invalid skill file path: #{rel_path}"
        end

        def within_dir?(base_dir, target_path)
          base = base_dir.to_s
          target = target_path.to_s
          return true if target == base

          target.start_with?(dir_prefix(base))
        end

        def dir_prefix(path)
          path = path.to_s
          path.end_with?(File::SEPARATOR) ? path : (path + File::SEPARATOR)
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

        def read_file_prefix(path, max_bytes:, label:)
          max_bytes = Integer(max_bytes)
          raise ArgumentError, "max_bytes must be positive" if max_bytes <= 0

          raw =
            File.open(path, "rb") do |io|
              io.read(max_bytes + 1)
            end
          raw = raw.to_s

          truncated = raw.bytesize > max_bytes
          data = truncated ? raw.byteslice(0, max_bytes).to_s : raw

          [data, truncated]
        rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::EINVAL, SystemCallError => e
          raise ArgumentError, "Failed to read #{label}: #{e.class}: #{e.message}"
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
