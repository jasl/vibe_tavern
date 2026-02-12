# frozen_string_literal: true

require_relative "test_helper"

class MCPSnapshotTest < Minitest::Test
  class Closeable
    attr_reader :closed

    def initialize
      @closed = false
    end

    def close
      @closed = true
    end
  end

  class ExplodingCloseable
    def close
      raise "boom"
    end
  end

  def test_close_calls_close_on_all_clients_and_swallows_errors
    ok = Closeable.new

    snapshot =
      TavernKit::VibeTavern::Tools::MCP::Snapshot.new(
        definitions: [],
        mapping: {},
        clients: {
          "ok" => ok,
          "boom" => ExplodingCloseable.new,
        },
      )

    snapshot.close
    assert_equal true, ok.closed
  end
end
