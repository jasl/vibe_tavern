class Result
  attr_reader :value, :errors, :code

  def self.success(value: nil, code: nil)
    new(success: true, value: value, errors: [], code: code)
  end

  def self.failure(errors:, code: nil, value: nil)
    new(success: false, value: value, errors: normalize_errors(errors), code: code)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  private

  def self.normalize_errors(errors)
    messages =
      if errors.respond_to?(:full_messages)
        errors.full_messages
      else
        Array(errors)
      end

    messages.compact.map(&:to_s)
  end

  def initialize(success:, value:, errors:, code:)
    @success = !!success
    @value = value
    @code = code
    @errors = Array(errors).freeze

    freeze
  end
end
