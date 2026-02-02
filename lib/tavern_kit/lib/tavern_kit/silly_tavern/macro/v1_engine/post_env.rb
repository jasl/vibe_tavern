# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      class V1Engine < TavernKit::Macro::Engine::Base
        private

        def expand_post_env(str, env, raw_content_hash)
          out = str.to_s
          return out if out.empty?

          out = out.gsub(/\{\{reverse:(.+?)\}\}/i) do |match|
            args = Regexp.last_match(1).to_s
            post_process(env, args.reverse, fallback: match)
          end

          # ST comment blocks: {{// ... }} removed.
          out = out.gsub(/\{\{\/\/[\s\S]*?\}\}/m, "")

          out = out.gsub(/\{\{outlet::(.+?)\}\}/i) do |match|
            offset = Regexp.last_match.begin(0) || 0
            key = Regexp.last_match(1).to_s.strip
            inv = Invocation.new(
              raw_inner: "outlet::#{key}",
              key: "outlet",
              name: :outlet,
              args: key,
              raw_args: [key],
              flags: Flags.empty,
              is_scoped: false,
              range: nil,
              offset: offset,
              raw_content_hash: raw_content_hash,
              environment: env,
              resolver: nil,
              trimmer: nil,
              warner: nil,
            )

            value =
              if inv.outlets.is_a?(Hash)
                inv.outlets[key] || inv.outlets[key.to_s] || ""
              else
                ""
              end

            post_process(env, value.to_s, fallback: match)
          end

          out = out.gsub(/\{\{random\s?::?([^}]+)\}\}/i) do |match|
            offset = Regexp.last_match.begin(0) || 0
            list_str = Regexp.last_match(1).to_s
            inv = Invocation.new(
              raw_inner: "random::#{list_str}",
              key: "random",
              name: :random,
              args: list_str,
              raw_args: [list_str],
              flags: Flags.empty,
              is_scoped: false,
              range: nil,
              offset: offset,
              raw_content_hash: raw_content_hash,
              environment: env,
              resolver: nil,
              trimmer: nil,
              warner: nil,
            )

            list = inv.split_list
            picked = list.empty? ? "" : list[inv.rng_or_new.rand(list.length)].to_s

            post_process(env, picked, fallback: match)
          end

          out = out.gsub(/\{\{pick\s?::?([^}]+)\}\}/i) do |match|
            offset = Regexp.last_match.begin(0) || 0
            list_str = Regexp.last_match(1).to_s
            inv = Invocation.new(
              raw_inner: "pick::#{list_str}",
              key: "pick",
              name: :pick,
              args: list_str,
              raw_args: [list_str],
              flags: Flags.empty,
              is_scoped: false,
              range: nil,
              offset: offset,
              raw_content_hash: raw_content_hash,
              environment: env,
              resolver: nil,
              trimmer: nil,
              warner: nil,
            )

            list = inv.split_list
            picked = list.empty? ? "" : list[inv.pick_index(list.length)].to_s

            post_process(env, picked, fallback: match)
          end

          out
        end

        def remove_unresolved_placeholders(str)
          s = str.to_s
          return s if s.empty?

          prev = nil
          cur = s
          5.times do
            break if cur == prev

            prev = cur
            cur = cur.gsub(/\{\{[^{}]*\}\}/, "")
          end

          cur
        end
      end
    end
  end
end
