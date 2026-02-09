# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TavernKit::PromptInspectorTest < Minitest::Test
  def build_estimator_with_hf_backend
    require "tokenizers"

    vocab = { "[UNK]" => 0, "hello" => 1, "world" => 2, "😁" => 3 }
    model = Tokenizers::Models::WordLevel.new(vocab: vocab, unk_token: "[UNK]")
    tok = Tokenizers::Tokenizer.new(model)
    tok.pre_tokenizer = Tokenizers::PreTokenizers::Whitespace.new

    file = Tempfile.new(["tokenizer", ".json"])
    tok.save(file.path)

    estimator =
      TavernKit::TokenEstimator.new(
        registry: {
          "oss-model" => { tokenizer_family: :hf_tokenizers, tokenizer_path: file.path },
        },
      )

    [estimator, file]
  end

  def test_inspect_messages_returns_full_detail_for_hf_backend
    estimator, tokenizer_json = build_estimator_with_hf_backend

    messages = [
      TavernKit::Prompt::Message.new(role: :user, content: "hello 😁"),
    ]

    inspection =
      TavernKit::PromptInspector.inspect_messages(
        messages,
        token_estimator: estimator,
        model_hint: "oss-model",
        message_overhead_tokens: 3,
      )

    assert_equal 1, inspection.totals.message_count
    assert_equal 3, inspection.messages.first.overhead_tokens

    tok = inspection.messages.first.content_tokenization
    assert_equal "hf_tokenizers", tok.backend
    assert_equal ["hello", "😁"], tok.tokens
    assert_equal [[0, 5], [6, 7]], tok.offsets
  ensure
    tokenizer_json&.close
    tokenizer_json&.unlink
  end

  def test_inspect_plan_matches_inspect_messages
    estimator, tokenizer_json = build_estimator_with_hf_backend

    plan =
      TavernKit::Prompt::Plan.new(
        blocks: [
          TavernKit::Prompt::Block.new(role: :user, content: "hello 😁"),
        ],
      )

    a =
      TavernKit::PromptInspector.inspect_plan(
        plan,
        token_estimator: estimator,
        model_hint: "oss-model",
      )

    b =
      TavernKit::PromptInspector.inspect_messages(
        plan.messages,
        token_estimator: estimator,
        model_hint: "oss-model",
      )

    assert_equal a.totals.total_tokens, b.totals.total_tokens
    assert_equal a.messages.first.content_tokenization.ids, b.messages.first.content_tokenization.ids
  ensure
    tokenizer_json&.close
    tokenizer_json&.unlink
  end

  def test_include_message_metadata_tokens_counts_metadata_even_when_json_fails
    estimator, tokenizer_json = build_estimator_with_hf_backend

    bad = "\xC3".b.force_encoding("UTF-8")
    metadata = { "bad" => bad }
    msg = TavernKit::Prompt::Message.new(role: :user, content: "hello", metadata: metadata)

    inspection =
      TavernKit::PromptInspector.inspect_messages(
        [msg],
        token_estimator: estimator,
        model_hint: "oss-model",
        include_message_metadata_tokens: true,
        include_metadata_details: true,
      )

    meta_serialized = metadata.to_s
    expected = estimator.estimate(meta_serialized, model_hint: "oss-model")

    assert_equal expected, inspection.messages.first.metadata_token_count
    assert inspection.messages.first.metadata_tokenization
  ensure
    tokenizer_json&.close
    tokenizer_json&.unlink
  end

  def test_hash_messages_treat_extra_keys_as_metadata
    estimator, tokenizer_json = build_estimator_with_hf_backend

    msg = { "role" => "user", "content" => "hello 😁", "tool_calls" => [{ "id" => "1" }] }

    inspection =
      TavernKit::PromptInspector.inspect_messages(
        [msg],
        token_estimator: estimator,
        model_hint: "oss-model",
        include_message_metadata_tokens: true,
      )

    assert inspection.messages.first.metadata_token_count.positive?
  ensure
    tokenizer_json&.close
    tokenizer_json&.unlink
  end
end
