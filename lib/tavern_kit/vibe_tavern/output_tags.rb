# frozen_string_literal: true

require_relative "text_masker"

module TavernKit
  module VibeTavern
    # Post-process assistant text by stripping/renaming XML-ish control tags.
    #
    # This is intended for tags that help prompt generation (e.g. `<lang ...>`)
    # but should not be shown to end users as-is.
    #
    # Configuration (runtime[:output_tags]) is programmer-owned and strict:
    #
    # ```ruby
    # runtime[:output_tags] = {
    #   enabled: true,
    #   escape_hatch: { enabled: true, mode: :html_entity },
    #   rules: [
    #     { tag: "think", action: :drop },
    #     { tag: "lang", action: :strip },
    #     { tag: "lang", action: :rename, to: "span", attrs: { "code" => "data-lang" } },
    #   ],
    #   sanitizers: {
    #     lang_spans: { enabled: true, validate_code: true, auto_close: true, on_invalid_code: :strip },
    #   },
    #   warn: false,
    #   warner: nil,
    # }
    # ```
    #
    # External text is treated as tolerant input; sanitizer implementations
    # should be best-effort and must not modify verbatim zones (handled by
    # TextMasker).
    module OutputTags
      DEFAULT_ESCAPE_HATCH = { enabled: true, mode: :html_entity }.freeze

      class Registry
        def initialize
          @sanitizers = {}
        end

        def register_sanitizer(name, callable)
          raise ArgumentError, "name must be a Symbol" unless name.is_a?(Symbol)
          raise ArgumentError, "callable must respond to #call" unless callable.respond_to?(:call)

          @sanitizers[name] = callable
          self
        end

        def fetch_sanitizer(name)
          raise ArgumentError, "name must be a Symbol" unless name.is_a?(Symbol)

          @sanitizers.fetch(name)
        end
      end

      Rule =
        Data.define(:tag, :action, :to, :attrs) do
          def initialize(tag:, action:, to: nil, attrs: nil)
            raise ArgumentError, "tag must be present" if tag.to_s.strip.empty?
            raise ArgumentError, "action must be a Symbol" unless action.is_a?(Symbol)

            unless %i[strip drop rename].include?(action)
              raise ArgumentError, "unsupported action: #{action.inspect}"
            end

            to = to&.to_s
            if action == :rename && to.to_s.strip.empty?
              raise ArgumentError, "rename rule requires :to"
            end

            attrs = normalize_attrs(attrs)

            super(
              tag: tag.to_s,
              action: action,
              to: to,
              attrs: attrs,
            )
          end

          def normalize_attrs(raw)
            return nil if raw.nil?
            raise ArgumentError, "attrs must be a Hash" unless raw.is_a?(Hash)

            raw.each_with_object({}) do |(k, v), out|
              out[k.to_s] = v.to_s
            end
          end
          private :normalize_attrs
        end

      module_function

      def registry
        @registry ||= Registry.new
      end

      def enabled?(runtime)
        cfg = config(runtime)
        return false unless cfg

        TavernKit::Coerce.bool(cfg.fetch(:enabled), default: false)
      end

      def transform(text, runtime:)
        cfg = config(runtime)
        return text.to_s unless cfg

        enabled = TavernKit::Coerce.bool(cfg.fetch(:enabled), default: false)
        return text.to_s unless enabled

        escape_hatch = escape_hatch_config(cfg.fetch(:escape_hatch, DEFAULT_ESCAPE_HATCH))
        rules = rules_config(cfg.fetch(:rules, []))
        sanitizers = sanitizers_config(cfg.fetch(:sanitizers, {}))

        warn_to_stderr = TavernKit::Coerce.bool(cfg.fetch(:warn, false), default: false)

        warner = cfg.fetch(:warner, nil)
        raise ArgumentError, "output_tags.warner must respond to #call" unless warner.nil? || warner.respond_to?(:call)

        has_escape = escape_hatch[:enabled] == true && text.to_s.include?("\\<")
        has_sanitizers = sanitizers.any? { |_name, scfg| scfg.fetch(:enabled) == true }

        return text.to_s if rules.empty? && !has_sanitizers && !has_escape

        masked_text, placeholders =
          TavernKit::VibeTavern::TextMasker.mask(
            text.to_s,
            escape_hatch: escape_hatch,
          )

        sanitized_text = masked_text
        warnings = []

        sanitizers.each do |name, scfg|
          next unless scfg.fetch(:enabled) == true

          sanitizer = registry.fetch_sanitizer(name)
          out_text, out_warnings = sanitizer.call(sanitized_text, scfg)
          sanitized_text = out_text.to_s
          warnings.concat(Array(out_warnings).map(&:to_s))
        rescue StandardError => e
          warnings << "output_tags.sanitizers.#{name}: #{e.class}: #{e.message}"
        end

        transformed = rules.empty? ? sanitized_text : apply_rules(sanitized_text, rules)
        restored = TavernKit::VibeTavern::TextMasker.unmask(transformed, placeholders)

        emit_warnings(warnings, warn_to_stderr: warn_to_stderr, warner: warner) if warnings.any?

        restored
      end

      def config(runtime)
        return nil unless runtime
        raise ArgumentError, "runtime must respond to #[]" unless runtime.respond_to?(:[])

        cfg = runtime[:output_tags]
        return nil if cfg.nil?

        raise ArgumentError, "runtime[:output_tags] must be a Hash" unless cfg.is_a?(Hash)

        cfg
      end
      private_class_method :config

      def escape_hatch_config(raw)
        raise ArgumentError, "output_tags.escape_hatch must be a Hash" unless raw.is_a?(Hash)

        enabled = TavernKit::Coerce.bool(raw.fetch(:enabled), default: false)

        mode = raw.fetch(:mode)
        raise ArgumentError, "output_tags.escape_hatch.mode must be a Symbol" unless mode.is_a?(Symbol)
        unless TavernKit::VibeTavern::TextMasker::ESCAPE_MODES.include?(mode)
          raise ArgumentError, "output_tags.escape_hatch.mode not supported: #{mode.inspect}"
        end

        { enabled: enabled, mode: mode }
      end
      private_class_method :escape_hatch_config

      def rules_config(raw)
        raise ArgumentError, "output_tags.rules must be an Array" unless raw.is_a?(Array)

        raw.map do |item|
          raise ArgumentError, "output_tags.rules entries must be Hash" unless item.is_a?(Hash)

          Rule.new(
            tag: item.fetch(:tag),
            action: item.fetch(:action),
            to: item.fetch(:to, nil),
            attrs: item.fetch(:attrs, nil),
          )
        end
      end
      private_class_method :rules_config

      def sanitizers_config(raw)
        raise ArgumentError, "output_tags.sanitizers must be a Hash" unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(k, v), out|
          raise ArgumentError, "sanitizer name must be a Symbol" unless k.is_a?(Symbol)
          raise ArgumentError, "sanitizer #{k} config must be a Hash" unless v.is_a?(Hash)

          enabled = TavernKit::Coerce.bool(v.fetch(:enabled), default: false)

          out[k] = v.merge(enabled: enabled)
        end
      end
      private_class_method :sanitizers_config

      def emit_warnings(warnings, warn_to_stderr:, warner:)
        Array(warnings).each do |w|
          if warner
            warner.call(w.to_s)
          elsif warn_to_stderr
            warn w
          end
        end
      end
      private_class_method :emit_warnings

      def apply_rules(text, rules)
        out = text.to_s

        Array(rules).each do |rule|
          tag = rule.tag.to_s.strip
          next if tag.empty?

          tag_re = Regexp.escape(tag)
          pattern = /<#{tag_re}\b([^>]*)>(.*?)<\/#{tag_re}\s*>/im

          case rule.action
          when :drop
            out = out.gsub(pattern, "")
          when :strip
            out = out.gsub(pattern, "\\2")
          when :rename
            out = out.gsub(pattern) do
              raw_attrs = Regexp.last_match(1).to_s
              inner = Regexp.last_match(2).to_s
              new_tag = rule.to.to_s
              new_attrs = rewrite_attrs(raw_attrs, rule.attrs)
              "<#{new_tag}#{new_attrs}>#{inner}</#{new_tag}>"
            end
          end
        end

        out
      end
      private_class_method :apply_rules

      def rewrite_attrs(raw_attrs, mapping)
        pairs = parse_attrs(raw_attrs)
        return "" if pairs.empty?

        map =
          if mapping.is_a?(Hash)
            mapping.each_with_object({}) { |(k, v), out| out[k.to_s.downcase] = v.to_s }
          else
            {}
          end

        out_pairs =
          pairs.map do |key, value|
            key_s = key.to_s
            new_key = map.fetch(key_s.downcase, key_s)
            [new_key.to_s, value.to_s]
          end

        " " + out_pairs.map { |k, v| "#{k}=#{v}" }.join(" ")
      end
      private_class_method :rewrite_attrs

      def parse_attrs(raw_attrs)
        s = raw_attrs.to_s
        return [] if s.strip.empty?

        s.scan(/([a-zA-Z0-9_:-]+)\s*=\s*(".*?"|'.*?'|[^\s>]+)/m).map do |k, v|
          [k.to_s, v.to_s]
        end
      end
      private_class_method :parse_attrs
    end
  end
end
