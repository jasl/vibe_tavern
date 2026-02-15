# frozen_string_literal: true

module AgentCore
  module PromptBuilder
    # Default prompt pipeline: direct assembly with no macro expansion.
    #
    # Builds a prompt by:
    # 1. Using the system prompt as-is (with optional variable substitution)
    # 2. Injecting memory results as a system context section
    # 3. Including chat history messages
    # 4. Appending the current user message
    # 5. Collecting tool definitions (filtered by policy if present)
    class SimplePipeline < Pipeline
      def build(context:)
        system = build_system_prompt(context)
        messages = build_messages(context)
        tools = build_tools(context)
        options = context.agent_config.fetch(:llm_options, {})

        BuiltPrompt.new(
          system_prompt: system,
          messages: messages,
          tools: tools,
          options: options
        )
      end

      private

      def build_system_prompt(context)
        prompt = context.system_prompt.dup

        # Inject memory context if available
        if context.memory_results.any?
          memory_text = context.memory_results.map(&:content).join("\n\n")
          prompt = "#{prompt}\n\n<relevant_context>\n#{memory_text}\n</relevant_context>"
        end

        # Simple variable substitution: {{variable_name}}
        context.variables.each do |key, value|
          prompt = prompt.gsub("{{#{key}}}", value.to_s)
        end

        if context.skills_store
          begin
            fragment =
              Resources::Skills::PromptFragment.available_skills_xml(
                store: context.skills_store,
                include_location: context.include_skill_locations
              )
            prompt = "#{prompt}\n\n#{fragment}" unless fragment.to_s.empty?
          rescue StandardError
            # Skip skills fragment on any store/prompt rendering error.
          end
        end

        prompt
      end

      def build_messages(context)
        messages = []

        # Include chat history
        if context.chat_history
          context.chat_history.each { |msg| messages << msg }
        end

        # Append current user message
        if context.user_message
          messages << Message.new(role: :user, content: context.user_message)
        end

        messages
      end

      def build_tools(context)
        return [] unless context.tools_registry

        tools = context.tools_registry.definitions

        policy = context.tool_policy || Resources::Tools::Policy::DenyAll.new

        tools =
          begin
            policy.filter(tools: tools, context: context.execution_context)
          rescue StandardError
            []
          end

        tools
      end
    end
  end
end
