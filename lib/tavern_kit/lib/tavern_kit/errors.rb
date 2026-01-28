# frozen_string_literal: true

module TavernKit
  # Base error class for all TavernKit errors.
  class Error < StandardError; end

  # Raised when strict mode is enabled and a non-fatal warning is encountered.
  # This allows callers to opt into treating forward-compatibility warnings as hard errors.
  class StrictModeError < Error; end

  # Character card errors
  class InvalidCardError < Error; end
  class UnsupportedVersionError < Error; end

  module Png
    class ParseError < TavernKit::Error; end
    class WriteError < TavernKit::Error; end
  end

  module Lore
    class ParseError < TavernKit::Error; end
  end
end
