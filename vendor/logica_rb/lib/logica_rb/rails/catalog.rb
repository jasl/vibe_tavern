# frozen_string_literal: true

require "pathname"

module LogicaRb
  module Rails
    class Catalog
      def initialize(import_root: nil)
        @import_root = import_root
      end

      def import_root
        @import_root || LogicaRb::Rails.configuration.import_root || default_import_root
      end

      def import_roots
        root = import_root
        root = root.to_path if root.respond_to?(:to_path)

        roots = root.is_a?(Array) ? root : [root]
        roots.compact.map { |r| r.respond_to?(:to_path) ? r.to_path : r.to_s }.reject(&:empty?)
      end

      def files
        import_roots.flat_map { |root| Dir.glob(File.join(root.to_s, "**", "*.l")) }.sort.uniq
      end

      def resolve_file(file)
        self.class.resolve_file(file, import_root: import_root)
      end

      def predicates_for_file(path)
        source = File.read(path)
        parsed_rules = LogicaRb::Parser.parse_file(source, import_root: import_root_for_parser)["rule"]

        names = LogicaRb::Parser.defined_predicates(parsed_rules).to_a.map(&:to_s)
        names.reject { |p| p.start_with?("@") || p == "++?" }.sort
      end

      private

      def default_import_root
        return nil unless defined?(::Rails) && ::Rails.respond_to?(:root)

        ::Rails.root.join("app/logica")
      end

      def import_root_for_parser
        roots = import_roots
        return "" if roots.empty?
        return roots.first if roots.length == 1

        roots
      end

      def self.resolve_file(file, import_root:)
        file = file.to_s
        return File.realpath(file) if Pathname.new(file).absolute?

        roots =
          if import_root.is_a?(Array)
            import_root
          else
            [import_root]
          end

        roots = roots.compact.map { |r| r.respond_to?(:to_path) ? r.to_path : r.to_s }.reject(&:empty?)
        roots.each do |root|
          candidate = File.join(root.to_s, file)
          return File.realpath(candidate) if File.exist?(candidate)
        end

        File.realpath(File.join(roots.first.to_s, file))
      end
    end
  end
end
