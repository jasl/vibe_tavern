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
        memory_section_order = 200
        skills_section_order = 800

        base = substitute_variables(context.system_prompt.to_s, context.variables)

        sections = []

        if context.memory_results.any?
          memory_text = context.memory_results.map(&:content).join("\n\n")
          sections << { order: memory_section_order, content: "<relevant_context>\n#{memory_text}\n</relevant_context>" }
        end

        Array(context.prompt_injection_items).each do |item|
          next unless item.respond_to?(:system_section?) && item.system_section?
          if item.respond_to?(:allowed_in_prompt_mode?) && !item.allowed_in_prompt_mode?(context.prompt_mode)
            next
          end

          content =
            if item.respond_to?(:substitute_variables) && item.substitute_variables == true
              substitute_variables(item.content.to_s, context.variables)
            else
              item.content.to_s
            end

          sections << { order: item.order.to_i, content: content }
        end

        if context.skills_store
          begin
            fragment =
              Resources::Skills::PromptFragment.available_skills_xml(
                store: context.skills_store,
                include_location: context.include_skill_locations
              )
            unless fragment.to_s.empty?
              sections << { order: skills_section_order, content: fragment.to_s }
            end
          rescue StandardError
            # Skip skills fragment on any store/prompt rendering error.
          end
        end

        sections
          .each_with_index
          .sort_by { |(section, idx)| [section.fetch(:order), idx] }
          .each do |(section, _)|
            content = section.fetch(:content).to_s
            next if content.strip.empty?

            base = base.empty? ? content : "#{base}\n\n#{content}"
          end

        base
      end

      def build_messages(context)
        messages = []

        Array(context.prompt_injection_items)
          .select { |item| item.respond_to?(:preamble_message?) && item.preamble_message? }
          .each_with_index
          .sort_by { |(item, idx)| [item.order.to_i, idx] }
          .each do |(item, _)|
            if item.respond_to?(:allowed_in_prompt_mode?) && !item.allowed_in_prompt_mode?(context.prompt_mode)
              next
            end

            role = item.role.to_sym
            next unless role == :user || role == :assistant

            content = item.content.to_s
            next if content.strip.empty?

            messages << Message.new(role: role, content: content)
          end

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

      def substitute_variables(template, variables)
        out = template.to_s.dup
        (variables || {}).each do |key, value|
          out = out.gsub("{{#{key}}}", value.to_s)
        end
        out
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
