# frozen_string_literal: true

require_relative "test_helper"

class WorkspaceTest < Minitest::Test
  def test_patch_draft_is_atomic_when_an_op_fails
    workspace = TavernKit::VibeTavern::ToolCalling::Workspace.new

    before_etag = workspace.draft_etag

    error =
      assert_raises(ArgumentError) do
        workspace.patch_draft!(
          [
            { "op" => "set", "path" => "/draft/foo", "value" => "bar" },
            { "op" => "set", "path" => "/not-draft/bad", "value" => "oops" },
          ],
          etag: nil,
        )
      end

    assert_match(/path must start with \/draft\//, error.message)
    assert_nil workspace.draft["foo"], "expected first op to be rolled back"
    assert_equal before_etag, workspace.draft_etag
  end
end

