# frozen_string_literal: true

require_relative "test_helper"

class VibeTavernResultTest < Minitest::Test
  def test_success_builds_a_successful_result
    result = TavernKit::VibeTavern::Result.success(value: 123, code: :created)

    assert result.success?
    refute result.failure?
    assert_equal 123, result.value
    assert_equal [], result.errors
    assert_equal :created, result.code
  end

  def test_failure_builds_a_failed_result
    result = TavernKit::VibeTavern::Result.failure(errors: ["nope"], code: :invalid)

    refute result.success?
    assert result.failure?
    assert_equal ["nope"], result.errors
    assert_equal :invalid, result.code
  end

  def test_failure_normalizes_a_string_error
    result = TavernKit::VibeTavern::Result.failure(errors: "nope")

    assert_equal ["nope"], result.errors
  end

  def test_failure_can_normalize_an_object_responding_to_full_messages
    fake_errors = Struct.new(:full_messages).new(["a", "b"])
    result = TavernKit::VibeTavern::Result.failure(errors: fake_errors)

    assert_equal ["a", "b"], result.errors
  end

  def test_result_and_its_errors_are_frozen
    result = TavernKit::VibeTavern::Result.failure(errors: "nope")

    assert result.frozen?
    assert result.errors.frozen?
  end
end
