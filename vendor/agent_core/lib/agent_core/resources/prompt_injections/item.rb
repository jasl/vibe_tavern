# frozen_string_literal: true

module AgentCore
  module Resources
    module PromptInjections
      TARGETS = [:system_section, :preamble_message].freeze
      ROLES = [:user, :assistant].freeze
      PROMPT_MODES = [:full, :minimal].freeze

      Item =
        Data.define(
          :target,
          :content,
          :order,
          :prompt_modes,
          :role,
          :substitute_variables,
          :id,
          :metadata,
        ) do
          def initialize(
            target:,
            content:,
            order: 0,
            prompt_modes: PROMPT_MODES,
            role: nil,
            substitute_variables: false,
            id: nil,
            metadata: nil
          )
            t = target.to_sym
            raise ArgumentError, "target must be one of #{TARGETS.inspect} (got #{target.inspect})" unless TARGETS.include?(t)

            ord = Integer(order || 0, exception: false) || 0

            modes = Array(prompt_modes).map { |m| m.to_sym }.uniq
            modes = PROMPT_MODES if modes.empty?
            modes &= PROMPT_MODES
            modes = PROMPT_MODES if modes.empty?
            modes.freeze

            r = role.nil? ? nil : role.to_sym
            if t == :preamble_message
              raise ArgumentError, "preamble_message requires role" if r.nil?
              raise ArgumentError, "role must be one of #{ROLES.inspect} (got #{role.inspect})" unless ROLES.include?(r)
            else
              r = nil
            end

            safe = normalize_utf8(content)

            md = metadata
            md = md.is_a?(Hash) ? md : {}
            md = md.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }.freeze

            sv = substitute_variables == true
            sv = false unless t == :system_section

            super(
              target: t,
              content: safe.freeze,
              order: ord,
              prompt_modes: modes,
              role: r,
              substitute_variables: sv,
              id: id,
              metadata: md,
            )
          end

          def allowed_in_prompt_mode?(prompt_mode)
            prompt_modes.include?(prompt_mode.to_sym)
          rescue NoMethodError
            false
          end

          def system_section? = target == :system_section
          def preamble_message? = target == :preamble_message

          private

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
