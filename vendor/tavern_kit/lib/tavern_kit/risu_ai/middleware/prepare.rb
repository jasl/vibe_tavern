# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Middleware
      # Stage: prompt preparation.
      #
      # Responsibilities:
      # - Build scan messages for lorebook activation
      # - Run RisuAI::Lore::Engine
      # - Build initial prompt sections and assemble blocks via TemplateCards
      class Prepare < TavernKit::Prompt::Middleware::Base
        DEFAULT_DESCRIPTION_TEXT_BUILDER =
          lambda do |ctx|
            data = ctx.character&.data
            return "" unless data

            desc = data.respond_to?(:description) ? data.description.to_s : ""
            personality = data.respond_to?(:personality) ? data.personality.to_s : ""
            scenario = data.respond_to?(:scenario) ? data.scenario.to_s : ""

            parts = []
            parts << desc unless desc.strip.empty?
            parts << "Description of #{ctx.character.name}: #{personality}" unless personality.strip.empty?
            parts << "Circumstances and context of the dialogue: #{scenario}" unless scenario.strip.empty?

            parts.join("\n\n").strip
          end.freeze

        private

        def before(ctx)
          normalize_risuai_runtime!(ctx)

          ctx.token_estimator ||= TavernKit::TokenEstimator.default
          ctx.variables_store!

          template = extract_prompt_template(ctx.preset)
          ctx.warn("RisuAI preset is missing promptTemplate; using empty template") if template.nil?
          template ||= []

          lore_books = build_books(ctx)

          scan_messages = build_scan_messages(ctx)
          lore_engine = ctx.lore_engine || TavernKit::RisuAI::Lore::Engine.new(token_estimator: ctx.token_estimator)

          lore_input = TavernKit::RisuAI::Lore::ScanInput.new(
            messages: scan_messages,
            books: lore_books,
            budget: ctx[:risuai_lore_token_budget],
            warner: ctx.method(:warn),
            scan_depth: (ctx[:risuai_lore_scan_depth] || 50),
            recursive_scanning: ctx.key?(:risuai_recursive_scanning) ? (ctx[:risuai_recursive_scanning] == true) : true,
            full_word_matching: ctx[:risuai_full_word_matching] == true,
            greeting_index: ctx.greeting_index,
            chat_length: (ctx[:risuai_chat_length] || (TavernKit::ChatHistory.wrap(ctx.history).size + 1)),
            variables: ctx.variables_store,
          )

          ctx.lore_result = lore_engine.scan(lore_input)

          groups = build_groups(ctx)

          ctx[:risuai_template] = template
          ctx[:risuai_groups] = groups
        end

        # Ensure the application-owned runtime contract is available once at the
        # pipeline entrypoint so downstream middlewares can rely on it.
        def normalize_risuai_runtime!(ctx)
          return if ctx.runtime

          # Runtime input is provided by the application as `ctx[:runtime]`.
          raw = ctx.key?(:runtime) ? ctx[:runtime] : nil

          ctx.variables_store!
          ctx.runtime = TavernKit::RisuAI::Runtime.build(raw, context: ctx, strict: ctx.strict?)
        end

        def extract_prompt_template(preset)
          return nil if preset.nil?

          if preset.is_a?(Hash)
            acc = TavernKit::Utils::HashAccessor.wrap(preset)
            raw = acc.fetch("promptTemplate", "prompt_template", :promptTemplate, :prompt_template, default: nil)
            return Array(raw) if raw.is_a?(Array)
            return nil
          end

          if preset.respond_to?(:prompt_template)
            return Array(preset.prompt_template)
          end

          nil
        end

        def build_books(ctx)
          books = []

          Array(ctx.lore_books).each do |b|
            book = coerce_book(b)
            books << book if book
          end

          character_book = ctx.character&.data&.character_book
          book = coerce_book(character_book) if character_book
          books << book if book

          books
        end

        def coerce_book(value)
          return nil if value.nil?
          return value if value.is_a?(TavernKit::Lore::Book)

          return TavernKit::Lore::Book.from_h(value) if value.is_a?(Hash)

          nil
        rescue ArgumentError
          nil
        end

        def build_scan_messages(ctx)
          history = TavernKit::ChatHistory.wrap(ctx.history)

          lines = history.to_a.map { |m| m.content.to_s }
          user_text = ctx.user_message.to_s
          lines << user_text unless user_text.strip.empty?
          lines
        end

        def build_groups(ctx)
          groups = {
            persona: [],
            description: [],
            lorebook: [],
            authornote: [],
            post_everything: [],
            chats: [],
          }

          if ctx.user && ctx.user.respond_to?(:persona_text)
            persona = ctx.user.persona_text.to_s
            groups[:persona] << { role: :system, content: persona } unless persona.strip.empty?
          end

          if ctx.character&.respond_to?(:data)
            content = build_description_text(ctx, description_text_builder: option(:description_text_builder))
            groups[:description] << { role: :system, content: content } unless content.empty?
          end

          history = TavernKit::ChatHistory.wrap(ctx.history).to_a
          groups[:chats] = history.map(&:to_h)

          user_text = ctx.user_message.to_s
          unless user_text.strip.empty?
            groups[:chats] << { role: :user, content: user_text }
          end

          author_note = ctx[:risuai_author_note]
          if author_note && !author_note.to_s.strip.empty?
            groups[:authornote] << { role: :system, content: author_note.to_s }
          end

          groups
        end

        def build_description_text(ctx, description_text_builder:)
          builder = description_text_builder
          unless builder.nil? || builder.respond_to?(:call)
            ctx.warn("risu_ai.prepare.description_text_builder must respond to #call (ignoring)")
            builder = nil
          end

          builder ||= DEFAULT_DESCRIPTION_TEXT_BUILDER
          builder.call(ctx).to_s.strip
        rescue StandardError => e
          ctx.warn("risu_ai.prepare.description_text_builder error (using default): #{e.class}: #{e.message}")
          DEFAULT_DESCRIPTION_TEXT_BUILDER.call(ctx).to_s.strip
        end
      end
    end
  end
end
