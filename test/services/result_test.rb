require "test_helper"

class ResultTest < ActiveSupport::TestCase
  test "success builds a successful result" do
    result = Result.success(value: 123, code: :created)

    assert result.success?
    refute result.failure?
    assert_equal 123, result.value
    assert_equal [], result.errors
    assert_equal :created, result.code
  end

  test "failure builds a failed result" do
    result = Result.failure(errors: ["nope"], code: :invalid)

    refute result.success?
    assert result.failure?
    assert_equal ["nope"], result.errors
    assert_equal :invalid, result.code
  end

  test "failure normalizes a string error" do
    result = Result.failure(errors: "nope")

    assert_equal ["nope"], result.errors
  end

  test "result and its errors are frozen" do
    result = Result.failure(errors: "nope")

    assert result.frozen?
    assert result.errors.frozen?
  end
end
