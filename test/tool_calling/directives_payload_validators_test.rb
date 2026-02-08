# frozen_string_literal: true

require_relative "test_helper"

require "easy_talk"

require_relative "../../lib/tavern_kit/vibe_tavern/directives/validator"
require_relative "../../lib/tavern_kit/vibe_tavern/directives/payload_validators"

class DirectivesPayloadValidatorsTest < Minitest::Test
  class ShowFormPayload
    include EasyTalk::Model

    define_schema do
      property :form_id, String, min_length: 1
    end
  end

  def test_easy_talk_payload_validator_drops_invalid_directives_and_returns_warning
    validator =
      TavernKit::VibeTavern::Directives::PayloadValidators.easy_talk(
        "ui.show_form" => ShowFormPayload,
      )

    envelope = {
      "assistant_text" => "hi",
      "directives" => [
        { "type" => "ui.show_form", "payload" => { "form_id" => "" } },
      ],
    }

    result =
      TavernKit::VibeTavern::Directives::Validator.validate(
        envelope,
        allowed_types: ["ui.show_form"],
        payload_validator: validator,
      )

    assert_equal true, result.fetch(:ok)

    value = result.fetch(:value)
    assert_equal "hi", value.fetch("assistant_text")
    assert_equal [], value.fetch("directives")

    warnings = result.fetch(:warnings)
    w = warnings.find { |item| item[:code] == "PAYLOAD_INVALID" }
    refute_nil w
    assert_equal 0, w.fetch(:index)
    assert_equal "ui.show_form", w.fetch(:type)
  end

  def test_easy_talk_payload_validator_accepts_valid_payload
    validator =
      TavernKit::VibeTavern::Directives::PayloadValidators.easy_talk(
        "ui.show_form" => ShowFormPayload,
      )

    envelope = {
      "assistant_text" => "hi",
      "directives" => [
        { "type" => "ui.show_form", "payload" => { "form_id" => "character_form_v1" } },
      ],
    }

    result =
      TavernKit::VibeTavern::Directives::Validator.validate(
        envelope,
        allowed_types: ["ui.show_form"],
        payload_validator: validator,
      )

    assert_equal true, result.fetch(:ok)

    value = result.fetch(:value)
    assert_equal 1, value.fetch("directives").length
    assert_equal "ui.show_form", value.fetch("directives")[0].fetch("type")
    assert_equal "character_form_v1", value.fetch("directives")[0].fetch("payload").fetch("form_id")
    assert_equal [], result.fetch(:warnings)
  end
end
