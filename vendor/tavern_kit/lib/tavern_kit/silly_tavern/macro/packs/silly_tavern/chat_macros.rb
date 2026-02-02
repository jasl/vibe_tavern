# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      module Packs
        module SillyTavern
          def self.register_chat_macros(registry)
            registry.register("lastMessage") { |inv| last_message(inv).to_s }
            registry.register("lastMessageId") { |inv| last_message_id(inv).to_s }
            registry.register("lastUserMessage") { |inv| last_user_message(inv).to_s }
            registry.register("lastCharMessage") { |inv| last_char_message(inv).to_s }

            registry.register("firstIncludedMessageId") { |inv| first_included_message_id(inv).to_s }
            registry.register("firstDisplayedMessageId") { |inv| first_displayed_message_id(inv).to_s }

            registry.register("lastSwipeId") { |inv| last_swipe_id(inv).to_s }
            registry.register("currentSwipeId") { |inv| current_swipe_id(inv).to_s }
          end

          def self.chat(inv)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            attrs["chat"]
          end

          def self.last_message_id(inv, exclude_swipe_in_progress: true, &filter)
            messages = chat(inv)
            return "" unless messages.is_a?(Array) && !messages.empty?

            (messages.length - 1).downto(0) do |idx|
              raw = messages[idx]
              msg = raw.is_a?(Hash) ? raw : {}
              ha = TavernKit::Utils::HashAccessor.wrap(msg)

              if exclude_swipe_in_progress
                swipes = ha.fetch(:swipes, default: nil)
                swipe_id = ha.fetch(:swipe_id, :swipeId, default: nil)
                if swipes.is_a?(Array) && swipe_id.is_a?(Numeric) && swipe_id >= swipes.length
                  next
                end
              end

              next if filter && !filter.call(msg, ha)

              return idx
            end

            ""
          end

          def self.last_message(inv)
            messages = chat(inv)
            idx = last_message_id(inv)
            return "" unless idx.is_a?(Integer) && messages.is_a?(Array)

            msg = messages[idx]
            ha = TavernKit::Utils::HashAccessor.wrap(msg.is_a?(Hash) ? msg : {})
            ha.fetch(:mes, default: "").to_s
          end

          def self.last_user_message(inv)
            messages = chat(inv)
            idx =
              last_message_id(inv) do |_msg, ha|
                ha.bool(:is_user, :isUser, default: false) && !ha.bool(:is_system, :isSystem, default: false)
              end
            return "" unless idx.is_a?(Integer) && messages.is_a?(Array)

            msg = messages[idx]
            ha = TavernKit::Utils::HashAccessor.wrap(msg.is_a?(Hash) ? msg : {})
            ha.fetch(:mes, default: "").to_s
          end

          def self.last_char_message(inv)
            messages = chat(inv)
            idx =
              last_message_id(inv) do |_msg, ha|
                !ha.bool(:is_user, :isUser, default: false) && !ha.bool(:is_system, :isSystem, default: false)
              end
            return "" unless idx.is_a?(Integer) && messages.is_a?(Array)

            msg = messages[idx]
            ha = TavernKit::Utils::HashAccessor.wrap(msg.is_a?(Hash) ? msg : {})
            ha.fetch(:mes, default: "").to_s
          end

          def self.first_included_message_id(inv)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            ha = TavernKit::Utils::HashAccessor.wrap(attrs)

            value =
              ha.fetch(:first_included_message_id, :firstIncludedMessageId, default: nil) ||
                ha.dig(:chat_metadata, :last_in_context_message_id) ||
                ha.dig(:chatMetadata, :lastInContextMessageId)

            value.nil? ? "" : value.to_s
          end

          def self.first_displayed_message_id(inv)
            env = inv.environment
            attrs = env.respond_to?(:platform_attrs) ? env.platform_attrs : {}
            ha = TavernKit::Utils::HashAccessor.wrap(attrs)

            value =
              ha.fetch(:first_displayed_message_id, :firstDisplayedMessageId, default: nil) ||
                ha.dig(:chat_metadata, :first_displayed_message_id) ||
                ha.dig(:chatMetadata, :firstDisplayedMessageId)

            value.nil? ? "" : value.to_s
          end

          def self.last_swipe_id(inv)
            messages = chat(inv)
            idx = last_message_id(inv, exclude_swipe_in_progress: false)
            return "" unless idx.is_a?(Integer) && messages.is_a?(Array)

            msg = messages[idx]
            ha = TavernKit::Utils::HashAccessor.wrap(msg.is_a?(Hash) ? msg : {})
            swipes = ha.fetch(:swipes, default: nil)
            swipes.is_a?(Array) ? swipes.length.to_s : ""
          end

          def self.current_swipe_id(inv)
            messages = chat(inv)
            idx = last_message_id(inv, exclude_swipe_in_progress: false)
            return "" unless idx.is_a?(Integer) && messages.is_a?(Array)

            msg = messages[idx]
            ha = TavernKit::Utils::HashAccessor.wrap(msg.is_a?(Hash) ? msg : {})
            swipe_id = ha.fetch(:swipe_id, :swipeId, default: nil)
            swipe_id.is_a?(Numeric) ? (swipe_id.to_i + 1).to_s : ""
          end

          private_class_method :register_chat_macros, :chat, :current_swipe_id, :first_displayed_message_id,
            :first_included_message_id, :last_char_message, :last_message, :last_message_id, :last_swipe_id, :last_user_message
        end
      end
    end
  end
end
