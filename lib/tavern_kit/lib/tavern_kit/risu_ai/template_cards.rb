# frozen_string_literal: true

module TavernKit
  module RisuAI
    # Prompt template assembly for RisuAI (Wave 5d).
    #
    # Characterization source:
    # - resources/Risuai/src/ts/process/index.svelte.ts (promptTemplate + positionParser)
    # - resources/Risuai/src/ts/process/prompt.ts (PromptItem types + stChatConvert)
    module TemplateCards
      module_function

      POSITION_PLACEHOLDER = /\{\{position::(.+?)\}\}/.freeze

      # Convert a SillyTavern "STCHAT" preset JSON into a RisuAI promptTemplate.
      #
      # Characterization source:
      # resources/Risuai/src/ts/process/prompt.ts (stChatConvert)
      def st_chat_convert(preset_hash)
        pre = TavernKit::Utils.deep_stringify_keys(preset_hash.is_a?(Hash) ? preset_hash : {})
        prompts = Array(pre["prompts"]).select { |p| p.is_a?(Hash) }

        order = Array(pre.dig("prompt_order", 0, "order")).select { |o| o.is_a?(Hash) }

        find_prompt = lambda do |identifier|
          prompts.find { |p| p["identifier"].to_s == identifier.to_s }
        end

        template = []

        order.each do |entry|
          enabled = entry.key?("enabled") ? TavernKit::Coerce.bool(entry["enabled"], default: false) : true
          next unless enabled

          p = find_prompt.call(entry["identifier"])
          next unless p

          identifier = p["identifier"].to_s
          content = p["content"].to_s
          role = p["role"].to_s
          role = "system" if role.empty?

          case identifier
          when "main"
            template << { "type" => "plain", "type2" => "main", "text" => content, "role" => role }
          when "jailbreak", "nsfw"
            template << { "type" => "jailbreak", "type2" => "normal", "text" => content, "role" => role }
          when "dialogueExamples", "charPersonality", "scenario"
            next
          when "chatHistory"
            template << { "type" => "chat", "rangeStart" => 0, "rangeEnd" => "end" }
          when "worldInfoBefore"
            template << { "type" => "lorebook" }
          when "worldInfoAfter"
            next
          when "charDescription"
            template << { "type" => "description" }
          when "personaDescription"
            template << { "type" => "persona" }
          else
            template << { "type" => "plain", "type2" => "normal", "text" => content, "role" => role }
          end
        end

        assistant_prefill = pre["assistant_prefill"]
        if assistant_prefill && !assistant_prefill.to_s.empty?
          template << { "type" => "postEverything" }
          template << {
            "type" => "plain",
            "type2" => "main",
            "text" => "{{#if {{prefill_supported}}}}#{assistant_prefill}{{/if}}",
            "role" => "bot",
          }
        end

        template
      end

      # Assemble a prompt from a RisuAI promptTemplate.
      #
      # @param template [Array<Hash>] promptTemplate items
      # @param groups [Hash{Symbol,String => Array<Prompt::Message,Hash>}] prebuilt sections
      #   Supported keys (by default mapping):
      #   - :persona, :description, :lorebook, :authornote, :post_everything, :chats
      # @param lore_entries [Array<Lore::Entry>] activated lore entries (RisuAI::Lore::Engine)
      # @return [Array<Prompt::Block>]
      def assemble(template:, groups:, lore_entries: [])
        template = normalize_template(template)
        groups = normalize_groups(groups)

        lore = classify_lore_entries(lore_entries)

        # Lore entries can augment prepared groups (RisuAI behavior).
        groups = groups.merge(
          lorebook: groups[:lorebook] + lore[:normal],
          description: apply_description_lore(groups[:description], lore[:description]),
          post_everything: groups[:post_everything] + lore[:post_everything] + lore[:post_everything_assistant],
        )

        injection_map = lore[:injection_by_location]
        position_map = lore[:position_by_name]

        blocks = []

        template.each do |raw|
          card = TavernKit::Utils.deep_stringify_keys(raw.is_a?(Hash) ? raw : {})
          type = card.fetch("type", "").to_s

          case type
          when "plain", "jailbreak", "cot"
            blocks.concat(build_plain_card(card, injection_map: injection_map, position_map: position_map))
          when "persona", "description", "lorebook", "postEverything", "memory"
            blocks.concat(build_typed_card(type, card, groups: groups, injection_map: injection_map, position_map: position_map))
          when "authornote"
            blocks.concat(build_author_note_card(card, groups: groups, injection_map: injection_map, position_map: position_map))
          when "chat"
            blocks.concat(build_chat_card(card, groups: groups))
          when "chatML"
            blocks.concat(build_chat_ml_card(card))
          when "cache"
            # Cache markers are represented as zero-length blocks with metadata.
            # (Dialect/request layers can interpret these.)
            blocks << TavernKit::Prompt::Block.new(
              role: :system,
              content: "",
              enabled: true,
              removable: false,
              token_budget_group: :default,
              metadata: { risuai: { type: "cache", name: card["name"], depth: card["depth"], role: card["role"] } },
            )
          else
            # Unknown cards are ignored (tolerant).
            next
          end
        end

        blocks.reject { |b| b.content.to_s.empty? }
      end

      def normalize_template(template)
        list = Array(template)

        has_post_everything = list.any? do |raw|
          h = raw.is_a?(Hash) ? raw : {}
          (h[:type] || h["type"]).to_s == "postEverything"
        end

        has_post_everything ? list : (list + [{ "type" => "postEverything" }])
      end

      def normalize_groups(groups)
        h = groups.is_a?(Hash) ? groups : {}
        {
          persona: normalize_message_list(h[:persona] || h["persona"]),
          description: normalize_message_list(h[:description] || h["description"]),
          lorebook: normalize_message_list(h[:lorebook] || h["lorebook"]),
          authornote: normalize_message_list(h[:authornote] || h["authornote"]),
          post_everything: normalize_message_list(h[:post_everything] || h["post_everything"] || h[:postEverything] || h["postEverything"]),
          chats: normalize_message_list(h[:chats] || h["chats"] || h[:chat] || h["chat"]),
        }
      end

      def normalize_message_list(value)
        Array(value).filter_map do |m|
          case m
          when TavernKit::Prompt::Message
            m
          when Hash
            role = (m[:role] || m["role"]).to_s
            role = "assistant" if role == "bot" || role == "char"
            content = m[:content] || m["content"] || m[:data] || m["data"] || ""
            TavernKit::Prompt::Message.new(role: role.to_sym, content: content.to_s)
          else
            nil
          end
        end
      end

      def classify_lore_entries(entries)
        actives = Array(entries)

        normal = []
        description = []
        post_everything = []
        post_everything_assistant = []

        injection_by_location = Hash.new { |h, k| h[k] = [] }
        position_by_name = Hash.new { |h, k| h[k] = [] }

        actives.each do |entry|
          next unless entry.is_a?(TavernKit::Lore::Entry)

          pos = entry.position.to_s
          meta = entry.extensions.is_a?(Hash) ? entry.extensions["risuai"] : nil
          meta = meta.is_a?(Hash) ? meta : {}

          depth = meta.fetch("depth", 0).to_i
          role = meta.fetch("role", "system").to_s

          inject = meta["inject"].is_a?(Hash) ? meta["inject"] : nil
          if inject && inject["lore"] != true
            loc = inject.fetch("location", "").to_s
            injection_by_location[loc] << {
              operation: inject.fetch("operation", "append").to_s,
              param: inject.fetch("param", "").to_s,
              prompt: entry.content.to_s,
            }
            next
          end

          if pos.start_with?("pt_")
            position_by_name[pos.delete_prefix("pt_")] << entry.content.to_s
            next
          end

          if pos == "" && inject.nil?
            normal << msg(entry)
            next
          end

          if %w[after_desc before_desc personality scenario].include?(pos)
            description << { pos: pos, msg: msg(entry) }
            next
          end

          if pos == "depth" && depth == 0
            if role == "assistant"
              post_everything_assistant << msg(entry)
            else
              post_everything << msg(entry)
            end
            next
          end
        end

        {
          normal: normal,
          description: description,
          post_everything: post_everything,
          post_everything_assistant: post_everything_assistant,
          injection_by_location: injection_by_location,
          position_by_name: position_by_name,
        }
      end

      def msg(entry)
        meta = entry.extensions.is_a?(Hash) ? entry.extensions["risuai"] : nil
        meta = meta.is_a?(Hash) ? meta : {}

        role = meta.fetch("role", "system").to_s
        role = "assistant" if role == "bot" || role == "char"

        TavernKit::Prompt::Message.new(role: role.to_sym, content: entry.content.to_s)
      end

      def apply_description_lore(base, desc_actives)
        list = base.dup
        Array(desc_actives).each do |h|
          pos = h[:pos].to_s
          m = h[:msg]
          next unless m.is_a?(TavernKit::Prompt::Message)

          if pos == "before_desc"
            list.unshift(m)
          else
            list << m
          end
        end
        list
      end

      def build_plain_card(card, injection_map:, position_map:)
        role = card.fetch("role", "system").to_s
        role = "assistant" if role == "bot"

        type = card.fetch("type", "").to_s
        type2 = card.fetch("type2", "normal").to_s
        loc = (type == "plain") ? type2 : type

        text = card.fetch("text", "").to_s
        text = position_parser(text, loc: loc, injection_map: injection_map, position_map: position_map)

        [
          TavernKit::Prompt::Block.new(
            role: role.to_sym,
            content: text,
            token_budget_group: :system,
            metadata: { risuai: { type: type, type2: type2 } },
          ),
        ]
      end

      def build_typed_card(type, card, groups:, injection_map:, position_map:)
        key =
          case type
          when "postEverything" then :post_everything
          else
            type.to_sym
          end

        list = groups.fetch(key, [])

        inner = card["innerFormat"]
        return list.map { |m| block_from_message(m, token_budget_group: token_budget_group_for_typed(type), metadata: { risuai: { type: type } }) } if inner.nil?

        inner2 = position_parser(inner.to_s, loc: type, injection_map: injection_map, position_map: position_map)

        list.map do |m|
          content = inner2.gsub("{{slot}}", m.content.to_s)
          TavernKit::Prompt::Block.new(
            role: m.role,
            content: content,
            token_budget_group: token_budget_group_for_typed(type),
            metadata: { risuai: { type: type } },
          )
        end
      end

      def build_author_note_card(card, groups:, injection_map:, position_map:)
        list = groups.fetch(:authornote, [])
        default_text = card["defaultText"].to_s

        inner = card["innerFormat"]
        inner2 =
          if inner.nil?
            "{{slot}}"
          else
            position_parser(inner.to_s, loc: "authornote", injection_map: injection_map, position_map: position_map)
          end

        base = list.any? ? list : [TavernKit::Prompt::Message.new(role: :system, content: default_text)]

        base.map do |m|
          content = inner2.gsub("{{slot}}", m.content.to_s)
          TavernKit::Prompt::Block.new(
            role: m.role,
            content: content,
            token_budget_group: :system,
            metadata: { risuai: { type: "authornote" } },
          )
        end
      end

      def build_chat_card(card, groups:)
        list = groups.fetch(:chats, [])

        start = Integer(card.fetch("rangeStart", 0)) rescue 0
        finish = card.fetch("rangeEnd", "end")
        finish = finish == "end" ? list.length : (Integer(finish) rescue list.length)

        if start == -1000
          start = 0
          finish = list.length
        end

        start = list.length + start if start.negative?
        finish = list.length + finish if finish.negative?

        start = 0 if start.negative?
        finish = 0 if finish.negative?

        return [] if start >= finish

        slice = list[start...finish]
        slice.map { |m| block_from_message(m, token_budget_group: :history, metadata: { risuai: { type: "chat" } }) }
      end

      def build_chat_ml_card(card)
        text = card.fetch("text", "").to_s
        parse_chat_ml(text).map do |m|
          block_from_message(m, token_budget_group: :system, metadata: { risuai: { type: "chatML" } })
        end
      end

      def parse_chat_ml(text)
        s = text.to_s
        s = "@@system\n#{s}" unless s.start_with?("@@")

        parts = s.split(/@@@?(user|assistant|system)\n/)
        out = []

        i = 1
        while i < parts.length
          role = parts[i].to_s
          content = parts[i + 1].to_s.strip
          out << TavernKit::Prompt::Message.new(role: role.to_sym, content: content)
          i += 2
        end

        out
      end

      def position_parser(text, loc:, injection_map:, position_map:)
        s = text.to_s

        Array(injection_map[loc.to_s]).each do |inj|
          op = inj[:operation].to_s
          prompt = inj[:prompt].to_s
          param = inj[:param].to_s

          case op
          when "append"
            s = [s, prompt].join(" ").strip
          when "prepend"
            s = [prompt, s].join(" ").strip
          when "replace"
            s = s.gsub(param, prompt)
          end
        end

        s.gsub(POSITION_PLACEHOLDER) do
          name = Regexp.last_match(1).to_s
          Array(position_map[name]).join("\n")
        end
      end

      def token_budget_group_for_typed(type)
        case type
        when "lorebook" then :lore
        when "memory" then :lore
        when "chats" then :history
        else
          :system
        end
      end

      def block_from_message(message, token_budget_group:, metadata:)
        TavernKit::Prompt::Block.new(
          role: message.role,
          content: message.content.to_s,
          token_budget_group: token_budget_group,
          metadata: metadata,
        )
      end
    end
  end
end
