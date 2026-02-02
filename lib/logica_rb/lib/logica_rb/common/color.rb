# frozen_string_literal: true

module LogicaRb
  module Common
    module Color
      CHR_ERROR = "\e[91m"
      CHR_WARNING = "\e[1m"
      CHR_UNDERLINE = "\e[4m"
      CHR_END = "\e[0m"
      CHR_OK = "\e[92m"

      module_function

      def warn(message)
        "#{CHR_WARNING}#{message}#{CHR_END}"
      end

      def color(name)
        colors_map[name.to_s]
      end

      def colors_map
        {
          "error" => CHR_ERROR,
          "warning" => CHR_WARNING,
          "underline" => CHR_UNDERLINE,
          "ok" => CHR_OK,
          "end" => CHR_END,
        }
      end

      def format(pattern, args_dict = nil)
        args_dict ||= {}
        replacements = colors_map.merge(args_dict.transform_keys(&:to_s))
        pattern.gsub(/\{(\w+)\}/) { |m| replacements.fetch(Regexp.last_match(1), m) }
      end
    end
  end
end
