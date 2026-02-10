# frozen_string_literal: true

require "easy_talk"

module TavernKit
  module VibeTavern
    module Directives
      module PayloadValidators
        # Payload validator adapter for EasyTalk models.
        #
        # Usage:
        #
        #   class ShowFormPayload
        #     include EasyTalk::Model
        #     define_schema { property :form_id, String, min_length: 1 }
        #   end
        #
        #   validator =
        #     TavernKit::VibeTavern::Directives::PayloadValidators.easy_talk(
        #       "ui.show_form" => ShowFormPayload,
        #     )
        #
        # Then pass `payload_validator: validator` to `Directives::Validator.validate`.
        class EasyTalkAdapter
          DEFAULT_ERROR_CODE = "PAYLOAD_INVALID"
          DEFAULT_ERROR_FORMAT = :flat

          def initialize(models_by_type:, error_code: DEFAULT_ERROR_CODE, error_format: DEFAULT_ERROR_FORMAT)
            @models_by_type = normalize_models(models_by_type)
            @error_code = error_code.to_s
            @error_format = error_format.to_s.strip.empty? ? DEFAULT_ERROR_FORMAT : error_format.to_sym
          end

          def call(type, payload)
            model_class = @models_by_type[type.to_s]
            return nil unless model_class

            instance = model_class.new(payload.is_a?(Hash) ? payload : {})

            unless instance.respond_to?(:valid?) && instance.respond_to?(:errors)
              return {
                code: "PAYLOAD_VALIDATOR_INVALID_MODEL",
                details: { model: model_class.name.to_s },
              }
            end

            return nil if instance.valid?

            formatted =
              begin
                EasyTalk::ErrorFormatter.format(instance.errors, format: @error_format)
              rescue StandardError
                Array(instance.errors&.full_messages).map(&:to_s)
              end

            {
              code: @error_code,
              details: {
                format: @error_format,
                errors: formatted,
              },
            }
          end

          private

          def normalize_models(value)
            (value.is_a?(Hash) ? value : {}).each_with_object({}) do |(k, v), out|
              key = k.to_s.strip
              next if key.empty?
              next unless v.respond_to?(:new)

              out[key] ||= v
            end
          end
        end

        module_function

        def easy_talk(**kwargs)
          kwargs = kwargs.dup

          error_code = kwargs.delete(:error_code) || EasyTalkAdapter::DEFAULT_ERROR_CODE
          error_format = kwargs.delete(:error_format) || EasyTalkAdapter::DEFAULT_ERROR_FORMAT

          EasyTalkAdapter.new(
            models_by_type: kwargs,
            error_code: error_code,
            error_format: error_format,
          )
        end
      end
    end
  end
end
