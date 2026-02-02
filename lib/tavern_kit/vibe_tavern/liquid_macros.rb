# frozen_string_literal: true

module TavernKit
  module VibeTavern
    # Liquid-based macros for the Rails rewrite.
    #
    # This is app-owned (lives in `lib/`) and intentionally independent from
    # the ST/RisuAI macro engines. We use Liquid for readable templates and
    # implement VariablesStore access via:
    # - `var.*` / `global.*` reads (Drops)
    # - explicit write tags: `{% setvar mood = "happy" %}` etc.
    module LiquidMacros
      module_function

      def environment
        @environment ||= ::Liquid::Environment.build do |env|
          env.register_filter(TavernKit::VibeTavern::LiquidMacros::Filters::DeterministicRng)
          env.register_filter(TavernKit::VibeTavern::LiquidMacros::Filters::Time)

          env.register_tag("setvar", TavernKit::VibeTavern::LiquidMacros::Tags::SetVar)
          env.register_tag("setdefaultvar", TavernKit::VibeTavern::LiquidMacros::Tags::SetDefaultVar)
          env.register_tag("addvar", TavernKit::VibeTavern::LiquidMacros::Tags::AddVar)
          env.register_tag("incvar", TavernKit::VibeTavern::LiquidMacros::Tags::IncVar)
          env.register_tag("decvar", TavernKit::VibeTavern::LiquidMacros::Tags::DecVar)
          env.register_tag("deletevar", TavernKit::VibeTavern::LiquidMacros::Tags::DeleteVar)

          env.register_tag("setglobal", TavernKit::VibeTavern::LiquidMacros::Tags::SetGlobal)
          env.register_tag("addglobal", TavernKit::VibeTavern::LiquidMacros::Tags::AddGlobal)
          env.register_tag("incglobal", TavernKit::VibeTavern::LiquidMacros::Tags::IncGlobal)
          env.register_tag("decglobal", TavernKit::VibeTavern::LiquidMacros::Tags::DecGlobal)
          env.register_tag("deleteglobal", TavernKit::VibeTavern::LiquidMacros::Tags::DeleteGlobal)
        end
      end

      # Render Liquid template text with a prompt-building-safe environment.
      #
      # @param text [String]
      # @param assigns [Hash] liquid assigns (top-level variables)
      # @param variables_store [TavernKit::VariablesStore::Base, nil]
      # @param strict [Boolean] when true, missing variables/tags should raise
      # @param on_error [Symbol] :raise or :passthrough (return original text)
      def render(text, assigns: {}, variables_store: nil, strict: false, on_error: :passthrough, registers: {})
        source = text.to_s
        store = variables_store

        liquid_assigns = (assigns || {}).dup
        if store
          liquid_assigns["var"] ||= TavernKit::VibeTavern::LiquidMacros::VariablesDrop.new(store, scope: :local)
          liquid_assigns["global"] ||= TavernKit::VibeTavern::LiquidMacros::VariablesDrop.new(store, scope: :global)
        end

        template = ::Liquid::Template.parse(source, environment: environment)

        out =
          template.render(
          liquid_assigns,
          registers: registers.merge(variables_store: store),
          strict_variables: strict,
          strict_filters: strict,
          ).to_s

        # ST-style escaping: `\{\{` / `\}\}` (or `\{` / `\}` generally) should be
        # preserved through parsing and unescaped after rendering.
        out = out.gsub(/\\([{}])/, "\\1")

        # Token hygiene: whitespace-only lines are equivalent to blank lines for
        # prompt-building/Markdown, but consume tokens. We only strip whitespace
        # on *blank* lines (never on content lines).
        out = out.gsub(/\A[ \t]+(?=\n)/, "")
        out = out.gsub(/(?<=\n)[ \t]+(?=\n)/, "")
        out = out.gsub(/(?<=\n)[ \t]+\z/, "")

        out
      rescue ::Liquid::Error
        raise if strict || on_error == :raise
        source
      end

      # Convenience: render using a prompt-building Context.
      #
      # @param ctx [TavernKit::Prompt::Context]
      # @param text [String]
      def render_for(ctx, text, strict: nil, on_error: :passthrough, registers: {})
        strict = strict.nil? ? (ctx.respond_to?(:strict?) ? ctx.strict? : false) : strict
        store = ctx.respond_to?(:variables_store) ? ctx.variables_store : nil
        runtime = ctx.respond_to?(:runtime) ? ctx.runtime : nil

        merged_registers = registers.is_a?(Hash) ? registers.dup : {}
        merged_registers[:runtime] ||= runtime if runtime

        render(
          text,
          assigns: TavernKit::VibeTavern::LiquidMacros::Assigns.build(ctx),
          variables_store: store,
          strict: strict,
          on_error: on_error,
          registers: merged_registers,
        )
      end
    end
  end
end
