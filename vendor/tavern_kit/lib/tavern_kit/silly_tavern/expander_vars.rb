# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Builds a Macro::Environment from a Prompt::Context for ST-compatible macro
    # expansion.
    #
    # This isolates "how do we map context state into macro expansion inputs"
    # into a single place so middleware can stay consistent.
    module ExpanderVars
      module_function

      def build(context, overrides: {})
        ctx = context

        character = ctx.respond_to?(:character) ? ctx.character : nil
        user = ctx.respond_to?(:user) ? ctx.user : nil
        preset = ctx.respond_to?(:preset) ? ctx.preset : nil

        vars_store =
          if ctx.respond_to?(:variables_store) && ctx.variables_store
            ctx.variables_store
          else
            TavernKit::VariablesStore::InMemory.new
          end

        macro_vars = ctx.respond_to?(:macro_vars) ? ctx.macro_vars : nil
        macro_acc = TavernKit::Utils::HashAccessor.wrap(macro_vars.is_a?(Hash) ? macro_vars : {})
        locals = macro_acc.fetch(:locals, default: nil)
        globals = macro_acc.fetch(:globals, default: nil)

        dynamic_macros = extract_dynamic_macros(macro_acc)

        user_message = ctx.respond_to?(:user_message) ? ctx.user_message.to_s : ""

        outlets = ctx.respond_to?(:outlets) ? ctx.outlets : {}

        group = ctx.respond_to?(:group) ? ctx.group : nil
        group_members = group_names(group_members(group))
        muted_members = group_names(group_muted(group))

        char_name = infer_char_name(character)
        user_name = infer_user_name(user)

        group_name =
          if group_members.any?
            group_members.join(", ")
          else
            char_name
          end

        group_not_muted =
          if group_members.any?
            (group_members - muted_members).join(", ")
          else
            char_name
          end

        not_char = build_not_char(group, group_members, char_name, user_name)

        content_hash = ctx.respond_to?(:[]) ? ctx[:content_hash] : nil

        platform_attrs = {
          input: user_message,
          max_prompt: preset&.respond_to?(:context_window_tokens) ? preset.context_window_tokens : nil,
          instruct: preset&.respond_to?(:effective_instruct) ? preset.effective_instruct : nil,
          context_template: preset&.respond_to?(:effective_context_template) ? preset.effective_context_template : nil,
          sysprompt_enabled: preset&.respond_to?(:use_sysprompt) ? (preset.use_sysprompt == true) : nil,
          prefer_character_prompt: preset&.respond_to?(:prefer_char_prompt) ? (preset.prefer_char_prompt == true) : nil,
          group_members: group_members,
          muted_members: muted_members,
          group_not_muted: group_not_muted,
          not_char: not_char,
        }.compact

        meta = ctx.respond_to?(:metadata) ? ctx.metadata : {}
        meta_acc = TavernKit::Utils::HashAccessor.wrap(meta.is_a?(Hash) ? meta : {})
        sysprompt_content = meta_acc.fetch(:sysprompt_content, :system_prompt_content, :default_system_prompt, default: nil)
        platform_attrs[:sysprompt_content] = sysprompt_content if sysprompt_content

        if overrides.is_a?(Hash)
          platform_attrs.merge!(overrides)
        end

        env =
          TavernKit::SillyTavern::Macro::Environment.new(
            character: character,
            user: user,
            variables: vars_store,
            locals: locals,
            globals: globals,
            outlets: outlets,
            original: user_message,
            content_hash: content_hash,
            character_name: char_name,
            user_name: user_name,
            group_name: group_name,
            extensions: dynamic_macros,
            **platform_attrs
          )

        env
      end

      def extract_dynamic_macros(macro_acc)
        raw = macro_acc.fetch(:dynamic_macros, :extensions, default: {})
        raw.is_a?(Hash) ? raw : {}
      end

      def group_members(group)
        return [] if group.nil?

        if group.is_a?(Hash)
          TavernKit::Utils::HashAccessor.wrap(group).fetch(:members, default: [])
        elsif group.respond_to?(:members)
          group.members || []
        else
          []
        end
      end

      def group_muted(group)
        return [] if group.nil?

        if group.is_a?(Hash)
          TavernKit::Utils::HashAccessor.wrap(group).fetch(:muted, default: [])
        elsif group.respond_to?(:muted)
          group.muted || []
        else
          []
        end
      end

      def group_names(list)
        Array(list).map { |m| m.respond_to?(:name) ? m.name : m.to_s }.map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def infer_char_name(character)
        return "" if character.nil?

        if character.respond_to?(:display_name)
          character.display_name.to_s
        elsif character.respond_to?(:name)
          character.name.to_s
        else
          character.to_s
        end
      end

      def infer_user_name(user)
        return "" if user.nil?

        user.respond_to?(:name) ? user.name.to_s : user.to_s
      end

      def build_not_char(group, members, char_name, user_name)
        return user_name if members.empty?

        current_char =
          if group.respond_to?(:current_character_or)
            group.current_character_or(char_name)
          else
            char_name
          end

        others = members.reject { |name| name == current_char }
        values = (others + [user_name]).map(&:to_s).map(&:strip).reject(&:empty?)
        values.any? ? values.join(", ") : user_name
      end

      private_class_method :extract_dynamic_macros, :group_members, :group_muted, :group_names,
        :infer_char_name, :infer_user_name, :build_not_char
    end
  end
end
