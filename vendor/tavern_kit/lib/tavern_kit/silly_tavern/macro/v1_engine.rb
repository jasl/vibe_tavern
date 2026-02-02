# frozen_string_literal: true

require "json"

require_relative "invocation"

module TavernKit
  module SillyTavern
    module Macro
      # Legacy SillyTavern-style macro expander (multi-pass regex).
      #
      # Compatibility goals:
      # - Case-insensitive macro names
      # - Multi-pass ordering so env substitutions can feed later macros
      # - Unknown macros are preserved by default (tolerant external input)
      class V1Engine < TavernKit::Macro::Engine::Base
        UNKNOWN_POLICIES = %i[keep empty].freeze

        def initialize(unknown: :keep)
          unless UNKNOWN_POLICIES.include?(unknown)
            raise ArgumentError, "unknown must be one of: #{UNKNOWN_POLICIES.inspect}"
          end
          @unknown = unknown
        end

        def expand(text, environment:)
          return "" if text.nil?

          str = text.to_s
          return str if str.empty?

          raw_content = str.dup
          raw_content_hash = Invocation.stable_hash(raw_content)

          env = environment

          # ST behavior: {{original}} expands at most once per evaluation.
          original_once = build_original_once(env)

          out = str.dup

          out = expand_pre_env(out, env, raw_content_hash)
          out = expand_env(out, env, raw_content_hash, original_once)
          out = expand_post_env(out, env, raw_content_hash)

          out = remove_unresolved_placeholders(out) if @unknown == :empty

          out
        end
      end
    end
  end
end

require_relative "v1_engine/pre_env"
require_relative "v1_engine/env"
require_relative "v1_engine/post_env"
