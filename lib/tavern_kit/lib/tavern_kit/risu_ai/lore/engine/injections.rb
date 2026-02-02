# frozen_string_literal: true

module TavernKit
  module RisuAI
    module Lore
      class Engine < TavernKit::Lore::Engine::Base
        private

        # Pure refactor: extracted from `risu_ai/lore/engine.rb`.
        def apply_lore_injections!(actives, injection_lores)
          list = Array(actives)

          Array(injection_lores).each do |lore|
            inject = lore.inject
            next unless inject

            idx = list.index { |a| a.source.to_s == inject.location.to_s }
            next unless idx

            found = list[idx]
            updated_content =
              case inject.operation
              when :append
                [found.content, lore.content].join(" ").strip
              when :prepend
                [lore.content, found.content].join(" ").strip
              when :replace
                found.content.to_s.gsub(inject.param.to_s, lore.content.to_s)
              else
                found.content
              end

            list[idx] = found.with(content: updated_content)
          end
        end

        # Pure refactor: extracted from `risu_ai/lore/engine.rb`.
        def to_result_entry(active)
          base = active.entry

          ext = base.extensions.dup
          ext["risuai"] ||= {}

          risu = ext["risuai"].is_a?(Hash) ? ext["risuai"].dup : {}
          risu["depth"] = active.depth
          risu["role"] = active.role.to_s
          risu["source"] = active.source
          if active.inject
            risu["inject"] = {
              "operation" => active.inject.operation.to_s,
              "location" => active.inject.location,
              "param" => active.inject.param,
              "lore" => active.inject.lore,
            }
          end
          ext["risuai"] = risu

          TavernKit::Lore::Entry.new(
            keys: base.keys,
            content: active.content,
            enabled: true,
            insertion_order: base.insertion_order,
            use_regex: base.use_regex,
            case_sensitive: base.case_sensitive,
            constant: base.constant,
            name: base.name,
            priority: base.priority,
            id: base.id,
            comment: base.comment,
            selective: base.selective,
            secondary_keys: base.secondary_keys,
            position: active.position,
            extensions: ext,
          )
        end
      end
    end
  end
end
