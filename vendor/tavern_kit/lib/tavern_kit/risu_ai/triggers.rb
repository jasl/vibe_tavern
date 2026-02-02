# frozen_string_literal: true

require_relative "triggers/local_vars"
require_relative "triggers/helpers"
require_relative "triggers/conditions"
require_relative "triggers/v2_collection_effects"
require_relative "triggers/v2_string_effects"
require_relative "triggers/v2_state_effects"
require_relative "triggers/runner"

module TavernKit
  module RisuAI
    # RisuAI trigger engine.
    #
    # This starts with the v1-style trigger schema used by characterization
    # tests (conditions + effect array). v2 effects are added iteratively.
    module Triggers
      Result = Data.define(:chat)

      # Upstream reference:
      # resources/Risuai/src/ts/process/triggers.ts (safeSubset/displayAllowList/requestAllowList)
      SAFE_SUBSET = %w[
        v2SetVar
        v2If
        v2IfAdvanced
        v2Else
        v2EndIndent
        v2LoopNTimes
        v2BreakLoop
        v2ConsoleLog
        v2StopTrigger
        v2Random
        v2ExtractRegex
        v2RegexTest
        v2GetCharAt
        v2GetCharCount
        v2ToLowerCase
        v2ToUpperCase
        v2SetCharAt
        v2SplitString
        v2JoinArrayVar
        v2ConcatString
        v2MakeArrayVar
        v2GetArrayVarLength
        v2GetArrayVar
        v2SetArrayVar
        v2PushArrayVar
        v2PopArrayVar
        v2ShiftArrayVar
        v2UnshiftArrayVar
        v2SpliceArrayVar
        v2SliceArrayVar
        v2GetIndexOfValueInArrayVar
        v2RemoveIndexFromArrayVar
        v2Calculate
        v2Comment
        v2DeclareLocalVar
      ].freeze

      DISPLAY_ALLOWLIST = (SAFE_SUBSET + %w[v2GetDisplayState v2SetDisplayState]).freeze
      REQUEST_ALLOWLIST = (SAFE_SUBSET + %w[v2GetRequestState v2SetRequestState v2GetRequestStateRole v2SetRequestStateRole v2GetRequestStateLength]).freeze

      module_function

      # Run a trigger list (the upstream "runTrigger" entrypoint).
      #
      # @param triggers [Array<Hash>] trigger scripts
      # @param chat [Hash] chat state (messages + scriptstate)
      # @param mode [String, Symbol, nil] optional type filter (e.g. "output")
      # @param manual_name [String, nil] runs only triggers whose comment matches (manual mode)
      # @param recursion_count [Integer] recursion guard for runtrigger
      def run_all(triggers, chat:, mode: nil, manual_name: nil, recursion_count: 0)
        t_list = normalize_triggers(triggers)
        c = deep_symbolize(chat.is_a?(Hash) ? chat : {})
        local_vars = LocalVars.new
        run_all_normalized(t_list, chat: c, mode: mode, manual_name: manual_name, recursion_count: recursion_count, local_vars: local_vars)
        Result.new(chat: c)
      end

      def run(trigger, chat:)
        t = TavernKit::Utils.deep_stringify_keys(trigger.is_a?(Hash) ? trigger : {})
        c = deep_symbolize(chat.is_a?(Hash) ? chat : {})

        # Note: `run` executes a single trigger unconditionally; it does not
        # filter by mode. However, request/display modes still apply effect
        # allowlists (mirroring upstream) to prevent unsafe side effects.
        _ = t.fetch("type", "").to_s

        conditions = Array(t["conditions"]).select { |v| v.is_a?(Hash) }
        effects = Array(t["effect"]).select { |v| v.is_a?(Hash) }

        local_vars = LocalVars.new

        return Result.new(chat: c) unless conditions_pass?(conditions, chat: c, local_vars: local_vars)

        run_effects(effects, chat: c, trigger: t, triggers: nil, recursion_count: 0, local_vars: local_vars)

        Result.new(chat: c)
      end

      def run_all_normalized(triggers, chat:, mode:, manual_name:, recursion_count:, local_vars:)
        triggers.each do |t|
          next unless t.is_a?(Hash)

          if manual_name
            next unless t["comment"].to_s == manual_name.to_s
          elsif mode
            next unless t["type"].to_s == mode.to_s
          end

          run_one_normalized(t, triggers: triggers, chat: chat, recursion_count: recursion_count, local_vars: local_vars)
        end
      end
      private_class_method :run_all_normalized

      def run_one_normalized(trigger, triggers:, chat:, recursion_count:, local_vars:)
        conditions = Array(trigger["conditions"]).select { |v| v.is_a?(Hash) }
        effects = Array(trigger["effect"]).select { |v| v.is_a?(Hash) }

        return unless conditions_pass?(conditions, chat: chat, local_vars: local_vars)

        run_effects(effects, chat: chat, trigger: trigger, triggers: triggers, recursion_count: recursion_count, local_vars: local_vars)
      end
      private_class_method :run_one_normalized

      # Implementation methods are split into:
      # - `risu_ai/triggers/runner.rb`
      # - `risu_ai/triggers/conditions.rb`
      # - `risu_ai/triggers/helpers.rb`
      # - `risu_ai/triggers/local_vars.rb`
      # - `risu_ai/triggers/v2_string_effects.rb`
      # - `risu_ai/triggers/v2_collection_effects.rb`
    end
  end
end
