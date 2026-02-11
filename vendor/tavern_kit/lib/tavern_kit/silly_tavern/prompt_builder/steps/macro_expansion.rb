# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module PromptBuilder
      module Steps
      # Expand {{macro}} syntax in block content via ST Macro engine.
      module MacroExpansion
        extend TavernKit::PromptBuilder::Step

        Config =
          Data.define do
            def self.from_hash(raw)
              return raw if raw.is_a?(self)

              raise ArgumentError, "macro_expansion step config must be a Hash" unless raw.is_a?(Hash)
              raw.each_key do |key|
                raise ArgumentError, "macro_expansion step config keys must be Symbols (got #{key.class})" unless key.is_a?(Symbol)
              end

              if raw.any?
                raise ArgumentError, "macro_expansion step does not accept step config keys: #{raw.keys.inspect}"
              end

              new
            end
          end

        def self.before(ctx, _config)
          ctx.expander ||= build_default_expander(ctx)

          env = TavernKit::SillyTavern::ExpanderVars.build(ctx)

          expanded = Array(ctx.blocks).map do |block|
            content = block.content.to_s
            next block if content.empty?

            begin
              block.with(content: ctx.expander.expand(content, environment: env))
            rescue TavernKit::SillyTavern::MacroError => e
              ctx.warn("Macro expansion error: #{e.class}: #{e.message}")
              block
            end
          end

          ctx.blocks = expanded
          ctx.instrument(:stat, step: ctx.current_step, key: :expanded_blocks, value: expanded.size)
        end

        class << self
          private

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
        end
      end
      end
    end
  end
end
