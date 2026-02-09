# frozen_string_literal: true

module TavernKit
  module VibeTavern
    # Small utility to "mask" verbatim zones and escaped tag openers before
    # applying regex-based transformations, then restore them deterministically.
    #
    # This helps prevent mis-parsing protocol/control tags that appear inside:
    # - fenced code blocks (```...```)
    # - inline code (`...`)
    # - Liquid-style macros ({{...}}, {%...%})
    #
    # It also supports an escape hatch for "semantic tags" where `\<` means:
    # - do not treat this `<` as the start of a control/protocol tag
    # - render it as plain text (configurable)
    module TextMasker
      ESCAPE_MODES = %i[html_entity literal keep_backslash].freeze
      DEFAULT_ESCAPE_HATCH = { enabled: true, mode: :html_entity }.freeze

      module_function

      def mask(text, escape_hatch:)
        escape_cfg = escape_hatch.nil? ? DEFAULT_ESCAPE_HATCH : escape_hatch
        escape_cfg = validate_escape_hatch!(escape_cfg)

        placeholders = {}
        counter = 0

        masked = text.to_s.dup

        protect = lambda do |pattern, prefix, &replacement|
          masked.gsub!(pattern) do |match|
            key = "\u0000VT#{prefix}#{counter}\u0000"
            counter += 1
            placeholders[key] = replacement ? replacement.call(match) : match
            key
          end
        end

        protect.call(/```.*?```/m, "CODE")
        protect.call(/`[^`]*`/, "INLINE")
        protect.call(/{{.*?}}/m, "LIQ")
        protect.call(/{%.*?%}/m, "LIQTAG")

        if escape_cfg.fetch(:enabled) == true
          escape_replacement = escape_replacement_for_mode(escape_cfg.fetch(:mode))
          protect.call(/\\</, "ESC") { escape_replacement }
        end

        [masked, placeholders]
      end

      def unmask(text, placeholders)
        out = text.to_s
        placeholders.each do |key, original|
          out = out.gsub(key, original.to_s)
        end
        out
      end

      def validate_escape_hatch!(raw)
        raise ArgumentError, "escape_hatch must be a Hash" unless raw.is_a?(Hash)

        enabled = TavernKit::Coerce.bool(raw.fetch(:enabled), default: false)

        mode = raw.fetch(:mode)
        raise ArgumentError, "escape_hatch.mode must be a Symbol" unless mode.is_a?(Symbol)
        raise ArgumentError, "escape_hatch.mode not supported: #{mode.inspect}" unless ESCAPE_MODES.include?(mode)

        { enabled: enabled, mode: mode }
      end
      private_class_method :validate_escape_hatch!

      def escape_replacement_for_mode(mode)
        case mode
        when :literal
          "<"
        when :keep_backslash
          "\\<"
        else
          "&lt;"
        end
      end
      private_class_method :escape_replacement_for_mode
    end
  end
end
