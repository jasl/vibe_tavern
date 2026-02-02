# frozen_string_literal: true

module TavernKit
  # Shared, low-overhead guardrails for untrusted regex usage.
  #
  # TavernKit accepts external inputs (cards, lorebooks, scripts) that may
  # contain user-provided regexes. We do not use regex timeouts; instead we
  # apply basic, predictable limits (pattern size and input size) to mitigate
  # common ReDoS risks.
  module RegexSafety
    DEFAULT_MAX_PATTERN_BYTES = 2048
    DEFAULT_MAX_INPUT_BYTES = 50_000

    module_function

    def compile(pattern, options: 0, max_pattern_bytes: DEFAULT_MAX_PATTERN_BYTES)
      return pattern if pattern.is_a?(Regexp)

      s = pattern.to_s
      return nil if s.empty?
      return nil if max_pattern_bytes.positive? && s.bytesize > max_pattern_bytes

      Regexp.new(s, options)
    rescue RegexpError
      nil
    end

    def input_too_large?(input, max_input_bytes: DEFAULT_MAX_INPUT_BYTES)
      max_input_bytes.positive? && input.to_s.bytesize > max_input_bytes
    rescue StandardError
      false
    end

    def match?(regex, input, max_input_bytes: DEFAULT_MAX_INPUT_BYTES)
      return false unless regex.is_a?(Regexp)

      s = input.to_s
      return false if max_input_bytes.positive? && s.bytesize > max_input_bytes

      regex.match?(s)
    rescue RegexpError
      false
    end

    def match(regex, input, max_input_bytes: DEFAULT_MAX_INPUT_BYTES)
      return nil unless regex.is_a?(Regexp)

      s = input.to_s
      return nil if max_input_bytes.positive? && s.bytesize > max_input_bytes

      regex.match(s)
    rescue RegexpError
      nil
    end
  end
end
