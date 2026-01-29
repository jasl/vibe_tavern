# frozen_string_literal: true

require "json"

module TavernKitTest
  module Fixtures
    module_function

    ROOT = File.expand_path("../fixtures", __dir__)

    def path(*parts)
      File.join(ROOT, *parts)
    end

    def read(*parts)
      File.read(path(*parts))
    end

    def json(*parts)
      JSON.parse(read(*parts))
    end
  end
end
