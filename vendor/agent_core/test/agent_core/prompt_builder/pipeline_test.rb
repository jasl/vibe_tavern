# frozen_string_literal: true

require "test_helper"

class AgentCore::PromptBuilder::PipelineTest < Minitest::Test
  def test_build_raises_not_implemented
    pipeline = AgentCore::PromptBuilder::Pipeline.new
    ctx = AgentCore::PromptBuilder::Context.new

    assert_raises(AgentCore::NotImplementedError) do
      pipeline.build(context: ctx)
    end
  end

  def test_subclass_can_implement_build
    custom_pipeline = Class.new(AgentCore::PromptBuilder::Pipeline) do
      def build(context:)
        AgentCore::PromptBuilder::BuiltPrompt.new(
          system_prompt: context.system_prompt,
          messages: [],
          tools: [],
        )
      end
    end

    ctx = AgentCore::PromptBuilder::Context.new(system_prompt: "Hello")
    result = custom_pipeline.new.build(context: ctx)

    assert_instance_of AgentCore::PromptBuilder::BuiltPrompt, result
    assert_equal "Hello", result.system_prompt
  end
end
