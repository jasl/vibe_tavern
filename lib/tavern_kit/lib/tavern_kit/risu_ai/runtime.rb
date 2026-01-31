# frozen_string_literal: true

module TavernKit
  module RisuAI
    # Application-owned runtime contract for RisuAI pipelines.
    #
    # This is the synchronization boundary between an app (chat state, settings)
    # and prompt building. Middlewares should assume `ctx[:risuai]` is normalized
    # once at pipeline entry.
    class Runtime < TavernKit::Runtime::Base
      def self.build(raw, context: nil, strict: false)
        data = normalize(raw, context: context, strict: strict)
        runtime = new(data)
        runtime.validate!(strict: strict)
        runtime
      end

      def self.normalize(raw, context: nil, strict: false)
        h = super(raw)

        out = h.dup
        out[:chat_index] = coerce_int(h, :chat_index, default: -1, strict: strict)
        out[:message_index] = coerce_message_index(h, context: context, strict: strict)
        out[:rng_word] = coerce_rng_word(h, context: context, strict: strict)

        out[:run_var] = coerce_bool(h, :run_var, default: true, strict: strict)
        out[:rm_var] = coerce_bool(h, :rm_var, default: false, strict: strict)

        out[:toggles] = coerce_hash(h, :toggles, default: {}, strict: strict)
        out[:metadata] = normalize_metadata(coerce_hash(h, :metadata, default: {}, strict: strict))
        out[:modules] = coerce_array(h, :modules, default: [], strict: strict)

        out
      end

      def validate!(strict: false)
        return self unless strict

        h = to_h
        validate_type!(h[:chat_index], Integer, key: :chat_index)
        validate_type!(h[:message_index], Integer, key: :message_index)
        validate_type!(h[:rng_word], String, key: :rng_word)
        validate_type!(h[:run_var], TrueClass, FalseClass, key: :run_var)
        validate_type!(h[:rm_var], TrueClass, FalseClass, key: :rm_var)
        validate_type!(h[:toggles], Hash, key: :toggles)
        validate_type!(h[:metadata], Hash, key: :metadata)
        validate_type!(h[:modules], Array, key: :modules)
        self
      end

      private_class_method def self.coerce_int(hash, key, default:, strict:)
        return default unless hash.key?(key)

        value = hash[key]
        return default if value.nil?
        return value if value.is_a?(Integer)
        return value.to_i if value.is_a?(Numeric)

        s = value.to_s.strip
        return default if s.empty?
        return Integer(s) if s.match?(/\A-?\d+\z/)

        raise ArgumentError, "Invalid RisuAI runtime #{key}: expected Integer" if strict

        default
      rescue ArgumentError, TypeError
        raise ArgumentError, "Invalid RisuAI runtime #{key}: expected Integer" if strict

        default
      end

      private_class_method def self.coerce_message_index(hash, context:, strict:)
        return coerce_int(hash, :message_index, default: 0, strict: strict) if hash.key?(:message_index)

        inferred = infer_history_size(context)
        inferred
      end

      private_class_method def self.infer_history_size(context)
        return 0 unless context

        history = context.respond_to?(:history) ? context.history : nil
        TavernKit::ChatHistory.wrap(history).size
      rescue ArgumentError
        0
      end

      private_class_method def self.coerce_rng_word(hash, context:, strict:)
        if hash.key?(:rng_word)
          return hash[:rng_word].to_s
        end

        # Upstream uses `chaId + chat.id` as the seed word. TavernKit cannot
        # infer those IDs, so fall back to character name unless app provides
        # a stable string via `ctx[:risuai][:rng_word]`.
        char = context && context.respond_to?(:character) ? context.character : nil
        name = char&.respond_to?(:name) ? char.name.to_s : ""

        return name unless name.strip.empty?
        return "0" unless strict

        raise ArgumentError, "Missing RisuAI runtime rng_word"
      end

      private_class_method def self.coerce_bool(hash, key, default:, strict:)
        return default unless hash.key?(key)

        value = hash[key]
        return default if value.nil?
        return value if value == true || value == false

        v = value.to_s.strip.downcase
        return true if TavernKit::Coerce::TRUE_STRINGS.include?(v)
        return false if TavernKit::Coerce::FALSE_STRINGS.include?(v)

        raise ArgumentError, "Invalid RisuAI runtime #{key}: expected Boolean" if strict

        default
      end

      private_class_method def self.coerce_hash(hash, key, default:, strict:)
        return default unless hash.key?(key)

        value = hash[key]
        return default if value.nil?
        return value if value.is_a?(Hash)

        raise ArgumentError, "Invalid RisuAI runtime #{key}: expected Hash" if strict

        default
      end

      private_class_method def self.coerce_array(hash, key, default:, strict:)
        return default unless hash.key?(key)

        value = hash[key]
        return default if value.nil?
        return Array(value) if value.is_a?(Array)

        raise ArgumentError, "Invalid RisuAI runtime #{key}: expected Array" if strict

        default
      end

      private_class_method def self.normalize_metadata(metadata)
        return {} unless metadata.is_a?(Hash)

        metadata.each_with_object({}) do |(k, v), out|
          # Match CBS macro normalization: lowercased and stripped of separators.
          key = k.to_s.downcase.gsub(/[\s_-]+/, "")
          out[key] = v
        end
      end

      def validate_type!(value, *klasses, key:)
        return if klasses.any? { |k| value.is_a?(k) }

        expected = klasses.map(&:name).join(" or ")
        raise ArgumentError, "Invalid RisuAI runtime #{key}: expected #{expected}"
      end
    end
  end
end
