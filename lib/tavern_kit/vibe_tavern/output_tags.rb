# frozen_string_literal: true

module TavernKit
  module VibeTavern
    # Post-process assistant text by stripping/renaming XML-ish control tags.
    #
    # This is intended for tags that help prompt generation (e.g. `<lang ...>`)
    # but should not be shown to end users as-is.
    #
    # Configuration is programmer-owned and strict. Context input is parsed via
    # `OutputTags::Config.from_context(context)`, then consumers call
    # `OutputTags.transform(text, config: config)`.
    #
    # Context shape:
    #
    # ```ruby
    # context[:output_tags] = {
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
    # TavernKit::Text::VerbatimMasker).
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

      Config =
        Data.define(
          :enabled,
          :escape_hatch,
          :rules,
          :sanitizers,
          :warn,
          :warner,
        ) do
          class << self
            def disabled
              new(
                enabled: false,
                escape_hatch: DEFAULT_ESCAPE_HATCH,
                rules: [],
                sanitizers: {},
                warn: false,
                warner: nil,
              )
            end

            def from_context(context)
              raw = context&.[](:output_tags)
              return disabled if raw.nil?

              raise ArgumentError, "context[:output_tags] must be a Hash" unless raw.is_a?(Hash)
              TavernKit::Utils.assert_symbol_keys!(raw, path: "output_tags")

              enabled = TavernKit::Coerce.bool(raw.fetch(:enabled, false), default: false)
              escape_hatch = parse_escape_hatch(raw.fetch(:escape_hatch, DEFAULT_ESCAPE_HATCH))
              rules = parse_rules(raw.fetch(:rules, []))
              sanitizers = parse_sanitizers(raw.fetch(:sanitizers, {}))
              warn_to_stderr = TavernKit::Coerce.bool(raw.fetch(:warn, false), default: false)

              warner = raw.fetch(:warner, nil)
              raise ArgumentError, "output_tags.warner must respond to #call" unless warner.nil? || warner.respond_to?(:call)

              new(
                enabled: enabled,
                escape_hatch: escape_hatch,
                rules: rules,
                sanitizers: sanitizers,
                warn: warn_to_stderr,
                warner: warner,
              )
            end

            private

            def parse_escape_hatch(raw)
              raise ArgumentError, "output_tags.escape_hatch must be a Hash" unless raw.is_a?(Hash)
              TavernKit::Utils.assert_symbol_keys!(raw, path: "output_tags.escape_hatch")

              enabled = TavernKit::Coerce.bool(raw.fetch(:enabled, false), default: false)
              mode = raw.fetch(:mode, :html_entity)
              raise ArgumentError, "output_tags.escape_hatch.mode must be a Symbol" unless mode.is_a?(Symbol)

              unless TavernKit::Text::VerbatimMasker::ESCAPE_MODES.include?(mode)
                raise ArgumentError, "output_tags.escape_hatch.mode not supported: #{mode.inspect}"
              end

              { enabled: enabled, mode: mode }
            end

            def parse_rules(raw)
              raise ArgumentError, "output_tags.rules must be an Array" unless raw.is_a?(Array)

              raw.map do |item|
                raise ArgumentError, "output_tags.rules entries must be Hash" unless item.is_a?(Hash)

                TavernKit::Utils.assert_symbol_keys!(item, path: "output_tags.rules[]")
                TavernKit::VibeTavern::OutputTags::Rule.new(
                  tag: item.fetch(:tag),
                  action: item.fetch(:action),
                  to: item.fetch(:to, nil),
                  attrs: item.fetch(:attrs, nil),
                )
              end
            end

            def parse_sanitizers(raw)
              raise ArgumentError, "output_tags.sanitizers must be a Hash" unless raw.is_a?(Hash)
              TavernKit::Utils.assert_symbol_keys!(raw, path: "output_tags.sanitizers")

              raw.each_with_object({}) do |(name, cfg), out|
                raise ArgumentError, "sanitizer name must be a Symbol" unless name.is_a?(Symbol)
                raise ArgumentError, "sanitizer #{name} config must be a Hash" unless cfg.is_a?(Hash)

                TavernKit::Utils.assert_symbol_keys!(cfg, path: "output_tags.sanitizers.#{name}")
                enabled = TavernKit::Coerce.bool(cfg.fetch(:enabled, false), default: false)

                out[name] = cfg.merge(enabled: enabled)
              end
            end
          end
        end

      module_function

      def registry
        @registry ||= Registry.new
      end

      def enabled?(config)
        normalize_config(config).enabled
      end

      def transform(text, config:)
        cfg = normalize_config(config)
        return text.to_s unless cfg.enabled

        escape_hatch = cfg.escape_hatch
        rules = cfg.rules
        sanitizers = cfg.sanitizers

        has_escape = escape_hatch[:enabled] == true && text.to_s.include?("\\<")
        has_sanitizers = sanitizers.any? { |_name, scfg| scfg.fetch(:enabled) == true }

        return text.to_s if rules.empty? && !has_sanitizers && !has_escape

        masked_text, placeholders =
          TavernKit::Text::VerbatimMasker.mask(
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
        restored = TavernKit::Text::VerbatimMasker.unmask(transformed, placeholders)

        emit_warnings(warnings, warn_to_stderr: cfg.warn, warner: cfg.warner) if warnings.any?

        restored
      end

      def normalize_config(config)
        return Config.disabled if config.nil?
        return config if config.is_a?(Config)

        raise ArgumentError, "output_tags config must be an OutputTags::Config"
      end
      private_class_method :normalize_config

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
        Array(rules).reduce(text.to_s) do |out, rule|
          tag = rule.tag.to_s.strip
          tag.empty? ? out : apply_rule(out, rule)
        end
      end
      private_class_method :apply_rules

      def apply_rule(text, rule)
        tag = rule.tag.to_s.strip
        return text.to_s if tag.empty?

        out = +""
        pos = 0
        depth = 0

        tag_re = /<\s*(\/?)\s*#{Regexp.escape(tag)}\b([^>]*)>/im

        while (m = tag_re.match(text, pos))
          out << text[pos...m.begin(0)] if rule.action != :drop || depth.zero?

          is_close = !m[1].to_s.empty?
          raw_attrs = m[2].to_s

          if is_close
            if depth.positive?
              depth -= 1
              out << "</#{rule.to}>" if rule.action == :rename
            end
          else
            depth += 1
            if rule.action == :rename
              new_attrs = rewrite_attrs(raw_attrs, rule.attrs)
              out << "<#{rule.to}#{new_attrs}>"
            end
          end

          pos = m.end(0)
        end

        out << text[pos..] if rule.action != :drop || depth.zero?

        if rule.action == :rename && depth.positive?
          out << ("</#{rule.to}>" * depth)
        end

        out
      end
      private_class_method :apply_rule

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
