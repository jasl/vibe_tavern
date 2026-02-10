# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
      # Build the final PromptBuilder::Plan.
      class PlanAssembly < TavernKit::PromptBuilder::Step
        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "plan_assembly step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "plan_assembly step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "plan_assembly step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        def self.before(ctx, _config)
          preset = ctx.preset
          blocks = Array(ctx.blocks)

          # These "control prompts" are inserted late (after macro expansion),
          # so we expand them explicitly to keep behavior consistent.
          ctx.expander ||= build_default_expander(ctx)
          env = TavernKit::SillyTavern::ExpanderVars.build(ctx)

          generation_type = ctx.generation_type.to_sym
          ctx.llm_options = build_llm_options(ctx, preset, env: env)

          if ctx.group && generation_type != :impersonate
            blocks = append_control_prompt(
              blocks,
              ctx,
              content: preset.group_nudge_prompt,
              env: env,
              source: :group_nudge,
              slot: :group_nudge_prompt,
            )
          end

          if generation_type == :continue
            blocks =
              if text_dialect?(ctx)
                apply_continue_text(blocks, ctx, preset, env: env)
              else
                apply_continue_chat(blocks, ctx, preset, env: env)
              end
          end

          if generation_type == :impersonate
            blocks = append_control_prompt(
              blocks,
              ctx,
              content: preset.impersonation_prompt,
              env: env,
              source: :impersonation_prompt,
              slot: :impersonation_prompt,
            )
          end

          blocks = apply_names_behavior(blocks, ctx)

          ctx.blocks = blocks

          ctx.plan = TavernKit::PromptBuilder::Plan.new(
            blocks: ctx.blocks,
            outlets: ctx.outlets,
            lore_result: ctx.lore_result,
            trim_report: ctx.trim_report,
            greeting: ctx.resolved_greeting,
            greeting_index: ctx.resolved_greeting_index,
            warnings: ctx.warnings,
            trace: nil,
            llm_options: ctx.llm_options,
          )

          ctx.instrument(:stat, step: ctx.current_step, key: :plan_blocks, value: ctx.blocks.size)
        end

        class << self
          private

        def build_llm_options(ctx, preset, env:)
          return {} unless claude_source?(ctx)

          type = ctx.generation_type.to_sym

          # ST parity: don't add a prefill on quiet gens (summarization) and when using continue prefill.
          return {} if type == :quiet
          return {} if type == :continue && preset.continue_prefill == true

          prefill =
            if type == :impersonate
              preset.assistant_impersonation.to_s
            else
              preset.assistant_prefill.to_s
            end

          prefill = expand_control_text(ctx, env: env, content: prefill, source: :assistant_prefill)
          prefill = prefill.to_s
          return {} if prefill.strip.empty?

          { assistant_prefill: prefill }
        end

        def claude_source?(ctx)
          meta = ctx.respond_to?(:metadata) ? ctx.metadata : {}
          acc = TavernKit::Utils::HashAccessor.wrap(meta)
          src = acc.fetch(:chat_completion_source, :chatCompletionSource, default: nil).to_s.strip.downcase
          src == "claude"
        end

        def append_control_prompt(blocks, ctx, content:, env:, source:, slot:)
          text = content.to_s
          return blocks if text.strip.empty?

          expanded = expand_control_text(ctx, env: env, content: text, source: source)

          blocks + [
            TavernKit::PromptBuilder::Block.new(
              role: :system,
              content: expanded.to_s,
              slot: slot,
              token_budget_group: :system,
              removable: false,
              metadata: { source: source },
            ),
          ]
        end

        def apply_continue_chat(blocks, ctx, preset, env:)
          if preset.continue_prefill == true
            append_continue_prefill_message(blocks, ctx, preset, env: env)
          else
            append_continue_nudge_message(blocks, ctx, preset, env: env)
          end
        end

        def apply_continue_text(blocks, ctx, preset, env:)
          if preset.continue_prefill == true
            apply_continue_prefill(blocks, ctx, preset, env: env)
          else
            append_control_prompt(
              blocks,
              ctx,
              content: preset.continue_nudge_prompt,
              env: env,
              source: :continue_nudge,
              slot: :continue_nudge_prompt,
            )
          end
        end

        def append_continue_prefill_message(blocks, ctx, preset, env:)
          displaced = ctx[:st_continue_prefill_block]
          return blocks unless displaced.is_a?(TavernKit::PromptBuilder::Block)

          content = displaced.content.to_s

          # Claude source parity: when using continue prefill, assistant_prefill is applied
          # by prepending it to the message to be continued, not via request options.
          if claude_source?(ctx) && displaced.role == :assistant
            expanded = expand_control_text(ctx, env: env, content: preset.assistant_prefill.to_s, source: :assistant_prefill)
            expanded = expanded.to_s.strip
            content = [expanded, content].reject(&:empty?).join("\n\n") unless expanded.empty?
          end

          blocks + [
            displaced.with(
              content: content,
              slot: :continue_prefill,
              token_budget_group: :system,
              removable: false,
              metadata: displaced.metadata.merge(source: :continue_prefill),
            ),
          ]
        end

        def append_continue_nudge_message(blocks, ctx, preset, env:)
          idx = blocks.rindex { |b| b.enabled? && b.slot == :chat_history && b.token_budget_group == :history }

          next_blocks =
            if idx.nil?
              blocks
            else
              target = blocks[idx]

              copy = blocks.dup
              copy.delete_at(idx)
              copy << target.with(
                slot: :continue_message,
                token_budget_group: :system,
                removable: false,
                metadata: target.metadata.merge(source: :continue_message),
              )
              copy
            end

          append_control_prompt(
            next_blocks,
            ctx,
            content: preset.continue_nudge_prompt,
            env: env,
            source: :continue_nudge,
            slot: :continue_nudge_prompt,
          )
        end

        def apply_continue_prefill(blocks, ctx, preset, env:)
          suffix = preset.continue_postfix.to_s
          assistant_prefill = preset.assistant_prefill.to_s

          idx = blocks.rindex { |b| b.enabled? && b.role == :assistant }
          return blocks if idx.nil?

          target = blocks[idx]
          new_content = target.content.to_s

          # Claude source parity: when using continue prefill, assistant_prefill is applied
          # by prepending it to the message to be continued, not via request options.
          if claude_source?(ctx)
            expanded = expand_control_text(ctx, env: env, content: assistant_prefill, source: :assistant_prefill)
            expanded = expanded.to_s.strip
            if !expanded.empty? && !new_content.start_with?(expanded)
              new_content = [expanded, new_content].reject(&:empty?).join("\n\n")
            end
          end

          new_content += suffix unless suffix.empty? || new_content.end_with?(suffix)

          copy = blocks.dup
          copy[idx] = target.with(content: new_content, metadata: target.metadata.merge(source: :continue_prefill))
          copy
        end

        def expand_control_text(ctx, env:, content:, source:)
          text = content.to_s
          return "" if text.empty?

          ctx.expander.expand(text, environment: env)
        rescue TavernKit::SillyTavern::MacroError => e
          ctx.warn("Macro expansion error in #{source}: #{e.class}: #{e.message}")
          text
        end

        def build_default_expander(ctx)
          builtins = TavernKit::SillyTavern::Macro::Packs::SillyTavern.default_registry

          custom = ctx.macro_registry
          if custom && !custom.respond_to?(:get)
            raise ArgumentError, "macro_registry must respond to #get"
          end

          registry =
            if custom
              TavernKit::SillyTavern::Macro::RegistryChain.new(custom, builtins)
            else
              builtins
            end

          TavernKit::SillyTavern::Macro::V2Engine.new(registry: registry)
        end

        def apply_names_behavior(blocks, ctx)
          behavior = ctx.preset&.names_behavior
          behavior = TavernKit::SillyTavern::Preset::NamesBehavior.coerce(behavior)

          user_name = ctx.user&.name.to_s
          group_chat = !ctx.group.nil?

          Array(blocks).map do |block|
            name = block.name.to_s.strip
            next block if name.empty?
            next block if block.role == :system
            next block if block.role == :tool
            next block if block.role == :function

            case behavior
            when TavernKit::SillyTavern::Preset::NamesBehavior::NONE
              block.with(name: nil)
            when TavernKit::SillyTavern::Preset::NamesBehavior::CONTENT
              block.with(content: prefix_name(block.content, name), name: nil)
            when TavernKit::SillyTavern::Preset::NamesBehavior::COMPLETION
              sanitized = sanitize_message_name(name)
              sanitized.empty? ? block.with(name: nil) : block.with(name: sanitized)
            else
              # DEFAULT behavior:
              # - in group chats, prefix non-user names into content
              # - always drop name field for chat completion payloads
              if group_chat && name != user_name
                block.with(content: prefix_name(block.content, name), name: nil)
              else
                block.with(name: nil)
              end
            end
          end
        end

        def prefix_name(content, name)
          prefix = "#{name.strip}: "
          str = content.to_s
          str.start_with?(prefix) ? str : "#{prefix}#{str}"
        end

        def sanitize_message_name(name)
          raw = name.to_s.strip
          return "" if raw.empty?

          # OpenAI name constraints are strict; keep this sanitizer simple and
          # deterministic (ST uses promptManager.sanitizeName()).
          raw
            .gsub(/\s+/, "_")
            .gsub(/[^a-zA-Z0-9_-]/, "_")
            .gsub(/_+/, "_")
            .slice(0, 64)
        end

        def text_dialect?(ctx)
          ctx.dialect.to_s.strip.downcase.to_sym == :text
        end
        end
      end
      end
    end
  end
end
