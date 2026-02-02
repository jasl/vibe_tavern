# frozen_string_literal: true

module TavernKit
  module SillyTavern
    # Group chat context helpers (SillyTavern parity).
    #
    # This class focuses on:
    # - decision sync between application scheduling and prompt-building
    # - activation strategy algorithms (NATURAL/LIST/MANUAL/POOLED)
    # - group card merging for APPEND/APPEND_DISABLED modes
    class GroupContext
      TALKATIVENESS_DEFAULT = 0.5

      Member = Data.define(:id, :name, :talkativeness)

      class << self
        # Compute a group activation decision.
        #
        # The returned hash is intentionally plain so apps can persist it.
        def decide(config:, input:)
          cfg = normalize_config(config)
          inp = normalize_input(input)

          rng = Random.new(inp.fetch(:seed))

          members = cfg.fetch(:members)
          disabled = cfg.fetch(:disabled_members)
          enabled = members.reject { |m| disabled.include?(m.id) }

          activated =
            case inp.fetch(:generation_type)
            when :continue, :swipe
              activate_swipe(enabled, chat: inp[:chat], allow_system: false, rng: rng)
            when :quiet
              activate_swipe(enabled, chat: inp[:chat], allow_system: true, rng: rng) || enabled.first&.id
            when :impersonate
              pick_one(enabled.map(&:id), rng: rng)
            else
              activate_by_strategy(cfg, inp, enabled, rng: rng)
            end

          {
            activated_member_ids: Array(activated).compact,
            strategy: cfg.fetch(:activation_strategy),
            generation_type: inp.fetch(:generation_type),
            is_user_input: inp.fetch(:is_user_input),
            seed: inp.fetch(:seed),
          }
        end

        # Merge multiple character cards into a single "group card" (ST append modes).
        #
        # Returns a hash compatible with ST `getGroupCharacterCardsLazy()` getters:
        # - :description
        # - :personality
        # - :scenario
        # - :mesExamples
        #
        # Note: this is structural join behavior only; macro expansion happens later.
        def merge_cards(config:, characters_by_id:, current_speaker_id:, overrides: {})
          cfg = normalize_merge_config(config)
          mode = cfg.fetch(:generation_mode)

          return nil unless %i[append append_disabled].include?(mode)

          members = cfg.fetch(:members)
          disabled = cfg.fetch(:disabled_members)

          join_prefix = cfg.fetch(:join_prefix)
          join_suffix = cfg.fetch(:join_suffix)

          scenario_override = overrides.fetch(:scenario, "").to_s.strip
          mes_examples_override = overrides.fetch(:mes_examples, "").to_s.strip

          scenario_value =
            if !scenario_override.empty?
              scenario_override
            else
              collect_field(
                members,
                characters_by_id,
                disabled_members: disabled,
                current_speaker_id: current_speaker_id,
                mode: mode,
                join_prefix: join_prefix,
                join_suffix: join_suffix,
                field_name: "Scenario",
              ) { |c| character_field(c, :scenario) }
            end

          mes_examples_value =
            if !mes_examples_override.empty?
              mes_examples_override
            else
              collect_field(
                members,
                characters_by_id,
                disabled_members: disabled,
                current_speaker_id: current_speaker_id,
                mode: mode,
                join_prefix: join_prefix,
                join_suffix: join_suffix,
                field_name: "Example Messages",
                preprocess: ->(v) { v.start_with?("<START>") ? v : "<START>\n#{v}" },
              ) { |c| character_field(c, :mes_example, :mes_examples) }
            end

          {
            description: collect_field(
              members,
              characters_by_id,
              disabled_members: disabled,
              current_speaker_id: current_speaker_id,
              mode: mode,
              join_prefix: join_prefix,
              join_suffix: join_suffix,
              field_name: "Description",
            ) { |c| character_field(c, :description) },
            personality: collect_field(
              members,
              characters_by_id,
              disabled_members: disabled,
              current_speaker_id: current_speaker_id,
              mode: mode,
              join_prefix: join_prefix,
              join_suffix: join_suffix,
              field_name: "Personality",
            ) { |c| character_field(c, :personality) },
            scenario: scenario_value,
            mesExamples: mes_examples_value,
          }
        end

        # Compare an app-provided decision to a TavernKit-computed decision.
        #
        # Returns true when the two decisions match (activated ids + strategy).
        def decision_matches?(a, b)
          ha = Utils::HashAccessor.wrap(a || {})
          hb = Utils::HashAccessor.wrap(b || {})

          Array(ha.fetch(:activated_member_ids, default: [])) == Array(hb.fetch(:activated_member_ids, default: [])) &&
            ha.fetch(:strategy, default: nil).to_s == hb.fetch(:strategy, default: nil).to_s
        end

        private

        def normalize_config(config)
          h = Utils::HashAccessor.wrap(config || {})
          strategy = h.fetch(:activation_strategy, default: :natural).to_s.downcase.to_sym

          members = Array(h.fetch(:members, default: [])).filter_map do |raw|
            member_hash = Utils::HashAccessor.wrap(raw.is_a?(Hash) ? raw : { id: raw, name: raw })
            id = member_hash.fetch(:id, default: nil)&.to_s
            next if id.nil? || id.empty?

            name = member_hash.fetch(:name, default: id).to_s
            talk = member_hash.fetch(:talkativeness, default: nil)
            talk = talk.to_f if talk.is_a?(Numeric) || talk.to_s.match?(/\A-?\d+(\.\d+)?\z/)

            Member.new(id: id, name: name, talkativeness: talk)
          end

          {
            activation_strategy: strategy,
            allow_self_responses: h.bool(:allow_self_responses, default: false),
            members: members,
            disabled_members: Array(h.fetch(:disabled_members, default: [])).map(&:to_s),
          }
        end

        def normalize_input(input)
          h = Utils::HashAccessor.wrap(input || {})

          {
            generation_type: Coerce.generation_type(h.fetch(:generation_type, default: :normal)),
            is_user_input: h.bool(:is_user_input, default: true),
            activation_text: h.fetch(:activation_text, default: "").to_s,
            last_speaker_id: h.fetch(:last_speaker_id, default: nil)&.to_s,
            seed: h.int(:seed, default: 0),
            chat: Array(h.fetch(:chat, default: nil)),
          }
        end

        def normalize_merge_config(config)
          h = Utils::HashAccessor.wrap(config || {})

          {
            generation_mode: h.fetch(:generation_mode, default: :swap).to_s.downcase.to_sym,
            members: Array(h.fetch(:members, default: [])).map(&:to_s),
            disabled_members: Array(h.fetch(:disabled_members, default: [])).map(&:to_s),
            join_prefix: h.fetch(:join_prefix, default: "").to_s,
            join_suffix: h.fetch(:join_suffix, default: "").to_s,
          }
        end

        def activate_by_strategy(cfg, inp, enabled, rng:)
          case cfg.fetch(:activation_strategy)
          when :list
            enabled.map(&:id)
          when :manual
            inp.fetch(:is_user_input) ? [] : pick_one(enabled.map(&:id), rng: rng)
          when :pooled
            activate_pooled(enabled, chat: inp[:chat], last_speaker_id: inp[:last_speaker_id], is_user_input: inp[:is_user_input], rng: rng)
          when :natural
            activate_natural(
              enabled,
              input_text: inp[:activation_text],
              last_speaker_id: inp[:last_speaker_id],
              allow_self_responses: cfg.fetch(:allow_self_responses),
              is_user_input: inp.fetch(:is_user_input),
              rng: rng,
            )
          else
            enabled.map(&:id)
          end
        end

        def activate_swipe(enabled_members, chat:, allow_system:, rng:)
          members_by_id = enabled_members.each_with_object({}) { |m, map| map[m.id] = m }

          messages = Array(chat)
          last = messages.last
          return nil unless last

          chosen = nil
          last_id = message_member_id(last)
          chosen = last_id if last_id && members_by_id.key?(last_id)

          if chosen.nil?
            messages.reverse_each do |msg|
              role = Coerce.role(message_role(msg), default: :assistant)
              next if role == :user
              next if role == :system && allow_system == false

              mid = message_member_id(msg)
              next unless mid && members_by_id.key?(mid)

              chosen = mid
              break
            end
          end

          chosen ||= pick_one(enabled_members.map(&:id), rng: rng).first
          chosen ? [chosen] : nil
        end

        def activate_pooled(enabled_members, chat:, last_speaker_id:, is_user_input:, rng:)
          enabled_ids = enabled_members.map(&:id)

          spoken_since_user = []
          Array(chat).reverse_each do |msg|
            break if is_user_input

            role = Coerce.role(message_role(msg), default: :assistant)
            break if role == :user
            next if role == :system

            mid = message_member_id(msg)
            spoken_since_user << mid if mid && enabled_ids.include?(mid)
          end

          have_not_spoken = enabled_ids - spoken_since_user.uniq
          pool =
            if have_not_spoken.any?
              have_not_spoken
            elsif enabled_ids.size > 1 && last_speaker_id && enabled_ids.include?(last_speaker_id)
              reduced = enabled_ids - [last_speaker_id]
              reduced.empty? ? enabled_ids : reduced
            else
              enabled_ids
            end

          pick_one(pool, rng: rng)
        end

        def activate_natural(enabled_members, input_text:, last_speaker_id:, allow_self_responses:, is_user_input:, rng:)
          enabled = enabled_members
          banned_id = (!allow_self_responses && !is_user_input) ? last_speaker_id : nil

          activated = []

          # 1) Mentions (preserve "first-seen" order like ST).
          input_words = extract_words(input_text)
          input_words.each do |input_word|
            enabled.each do |member|
              next if banned_id && member.id == banned_id

              if extract_words(member.name).include?(input_word)
                activated << member.id
                break
              end
            end
          end

          # 2) Talkativeness (shuffled order, excluding banned).
          chatty = []
          shuffle(enabled, rng: rng).each do |member|
            next if banned_id && member.id == banned_id

            roll = rng.rand
            talk = numeric_talkativeness(member.talkativeness)

            activated << member.id if talk >= roll
            chatty << member.id if talk > 0
          end

          # 3) Fallback: ensure at least one member.
          if activated.empty?
            pool = (chatty.empty? ? enabled.map(&:id) : chatty)
            pool = pool.reject { |id| banned_id && id == banned_id }
            pool = enabled.map(&:id) if pool.empty?
            activated.concat(pick_one(pool, rng: rng))
          end

          activated.uniq
        end

        def numeric_talkativeness(value)
          return TALKATIVENESS_DEFAULT if value.nil?
          return value if value.is_a?(Numeric)

          raw = value.to_s
          return TALKATIVENESS_DEFAULT unless raw.match?(/\A-?\d+(\.\d+)?\z/)

          raw.to_f
        end

        def extract_words(value)
          value.to_s.scan(/\b\w+\b/i).map(&:downcase)
        end

        def shuffle(list, rng:)
          list = list.dup
          # Fisher-Yates shuffle using the injected RNG.
          (list.length - 1).downto(1) do |i|
            j = rng.rand(0..i)
            list[i], list[j] = list[j], list[i]
          end
          list
        end

        def pick_one(list, rng:)
          list = Array(list)
          return [] if list.empty?

          [list[rng.rand(0...list.length)]]
        end

        def collect_field(
          members,
          characters_by_id,
          disabled_members:,
          current_speaker_id:,
          mode:,
          join_prefix:,
          join_suffix:,
          field_name:,
          preprocess: nil,
          &getter
        )
          values = []
          members.each do |member_id|
            character = characters_by_id[member_id.to_s]
            next unless character

            if disabled_members.include?(member_id.to_s) &&
                member_id.to_s != current_speaker_id.to_s &&
                mode != :append_disabled
              next
            end

            raw = getter.call(character).to_s.strip
            next if raw.empty?

            raw = preprocess.call(raw) if preprocess

            values << "#{replace_field_placeholder(join_prefix, field_name)}#{raw}#{replace_field_placeholder(join_suffix, field_name)}"
          end

          values.join("\n")
        end

        def replace_field_placeholder(template, field_name)
          template.to_s.gsub(/<FIELDNAME>/i, field_name.to_s)
        end

        def character_field(character, *keys)
          data = character.respond_to?(:data) ? character.data : character

          keys.each do |k|
            value =
              if data.respond_to?(k)
                data.public_send(k)
              elsif character.respond_to?(k)
                character.public_send(k)
              else
                nil
              end
            return value unless value.nil?
          end

          nil
        end

        def message_role(message)
          ha = Utils::HashAccessor.wrap(message)
          ha.fetch(:role, default: :assistant)
        end

        def message_member_id(message)
          ha = Utils::HashAccessor.wrap(message)
          ha.fetch(:member_id, :memberId, default: nil)&.to_s
        end
      end
    end
  end
end
