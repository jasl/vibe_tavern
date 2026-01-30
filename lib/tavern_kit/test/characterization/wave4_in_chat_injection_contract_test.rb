# frozen_string_literal: true

require "test_helper"

class Wave4InChatInjectionContractTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("../fixtures/silly_tavern/injects", __dir__)

  def pending!(reason)
    skip("Pending Wave 4 (Injection in-chat): #{reason}")
  end

  def test_in_chat_depth_and_role_order_matches_st_do_chat_inject
    pending!("Stage 5 must match ST doChatInject depth semantics + role ordering + concatenation")

    injects = JSON.parse(File.read(File.join(FIXTURES_DIR, "in_chat_order.json")))

    # Contract input (conceptual):
    # - chat history: m1, m2, m3 (m3 is most recent)
    # - in-chat injections at depth 1 and depth 0, with all roles present
    #
    # Expected output order (oldest -> newest) for generation_type :normal:
    #
    # m1
    # m2
    # AST D1 First\nAST D1 Second   (assistant, depth 1)
    # USR D1                       (user, depth 1)
    # SYS D1                       (system, depth 1)
    # m3
    # AST D0                       (assistant, depth 0)
    # USR D0                       (user, depth 0)
    # SYS D0                       (system, depth 0)
    #
    # Notes:
    # - For each (depth, role) group, entries are concatenated in lexicographic id order.
    # - No trailing newline is appended to the injected message content.
    _ = injects
  end

  def test_continue_shifts_depth_zero_injections_to_depth_one
    pending!("continue mode shifts depth 0 injections to behave like depth 1")

    injects = JSON.parse(File.read(File.join(FIXTURES_DIR, "in_chat_order.json")))

    # Expected output order for generation_type :continue:
    #
    # m1
    # m2
    # AST D1 First\nAST D1 Second
    # USR D1
    # SYS D1
    # AST D0
    # USR D0
    # SYS D0
    # m3
    #
    # Note: both depth=1 and depth=0 injections end up before the last message,
    # with deeper original depth appearing earlier (before shifted depth=0).
    _ = injects
  end
end
