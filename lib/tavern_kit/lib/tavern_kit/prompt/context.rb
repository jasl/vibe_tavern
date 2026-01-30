# frozen_string_literal: true

module TavernKit
  module Prompt
    # Context object that flows through the middleware pipeline.
    #
    # The context carries all input data, intermediate state, and output
    # through each middleware stage. Middlewares can read and modify the
    # context to transform inputs into the final prompt plan.
    class Context
      # ============================================
      # Input data (typically set at initialization)
      # ============================================

      # @return [Character, nil] the character card
      attr_accessor :character

      # @return [Participant, nil] the user/persona
      attr_accessor :user

      # @return [Object, nil] chat history
      attr_accessor :history

      # @return [String] current user message
      attr_accessor :user_message

      # @return [Object, nil] preset configuration
      attr_accessor :preset

      # @return [Symbol, nil] output dialect hint (:openai, :anthropic, :text, ...)
      #
      # Used by dialect-aware pipelines (e.g. SillyTavern) to branch between
      # chat-style assembly vs text-completion style assembly.
      attr_accessor :dialect

      # @return [Symbol] generation type (:normal, :continue, :impersonate, etc.)
      attr_accessor :generation_type

      # @return [Object, nil] group chat context
      attr_accessor :group

      # @return [Array] global lore books
      attr_accessor :lore_books

      # @return [Integer, nil] greeting index
      attr_accessor :greeting_index

      # @return [Hash, nil] per-chat Author's Note overrides
      attr_accessor :authors_note_overrides

      # @return [Array<Hash>] forced World Info activations
      attr_accessor :forced_world_info_activations

      # @return [Object, nil] injection registry
      attr_accessor :injection_registry

      # @return [Object, nil] hook registry
      attr_accessor :hook_registry

      # @return [Hash, nil] macro variables
      attr_accessor :macro_vars

      # ============================================
      # Intermediate state (set by middlewares)
      # ============================================

      # @return [Object, nil] lore engine evaluation result
      attr_accessor :lore_result

      # @return [Hash{String => Object}] World Info outlets
      attr_accessor :outlets

      # @return [Array<PromptEntry>] filtered prompt entries
      attr_accessor :prompt_entries

      # @return [Hash{String => Array<Block>}] pinned group blocks
      attr_accessor :pinned_groups

      # @return [Array<Block>] compiled blocks
      attr_accessor :blocks

      # @return [Array<Block>, nil] continue blocks for :continue generation
      attr_accessor :continue_blocks

      # @return [Object, nil] variables store
      attr_accessor :variables_store

      # @return [Array<String>] scan messages for World Info
      attr_accessor :scan_messages

      # @return [Hash] scan context for World Info
      attr_accessor :scan_context

      # @return [Array<String>] scan injects for World Info
      attr_accessor :scan_injects

      # @return [Array<String>] chat scan messages for prompt entry conditions
      attr_accessor :chat_scan_messages

      # @return [Integer] default chat depth for scanning
      attr_accessor :default_chat_depth

      # @return [Integer] user turn count
      attr_accessor :turn_count

      # ============================================
      # Output
      # ============================================

      # @return [Plan, nil] the final prompt plan
      attr_accessor :plan

      # @return [String, nil] resolved greeting text
      attr_accessor :resolved_greeting

      # @return [Integer, nil] resolved greeting index
      attr_accessor :resolved_greeting_index

      # @return [Hash, nil] trim report from Trimmer
      attr_accessor :trim_report

      # @return [Hash, nil] provider/request options derived during prompt build
      #
      # Example: Claude-style assistant prefill settings are expressed as request
      # options rather than message content.
      attr_accessor :llm_options

      # ============================================
      # Configuration
      # ============================================

      # @return [Object, nil] token estimator
      attr_accessor :token_estimator

      # @return [Object, nil] lore engine
      attr_accessor :lore_engine

      # @return [Object, nil] macro expander
      attr_accessor :expander

      # @return [Object, nil] custom macro registry
      attr_accessor :macro_registry

      # @return [Object, nil] builtins macro registry
      attr_accessor :macro_builtins_registry

      # @return [Object, nil] pinned group resolver
      attr_accessor :pinned_group_resolver

      # @return [Symbol, Proc, nil] warning handler
      attr_accessor :warning_handler

      # @return [Boolean] strict mode flag
      attr_accessor :strict

      # ============================================
      # Warnings and metadata
      # ============================================

      # @return [Prompt::Instrumenter::Base, nil] optional debug instrumenter
      attr_accessor :instrumenter

      # @return [Symbol, nil] current middleware stage name (internal)
      attr_accessor :current_stage

      # @return [Array<String>] collected warnings
      attr_reader :warnings

      # @return [Hash] arbitrary metadata storage
      attr_reader :metadata

      def initialize(**attrs)
        @warnings = []
        @metadata = {}
        @instrumenter = nil
        @current_stage = nil
        @lore_books = []
        @forced_world_info_activations = []
        @outlets = {}
        @pinned_groups = {}
        @blocks = []
        @generation_type = :normal
        @strict = false
        @warning_handler = :default

        attrs.each do |key, value|
          setter = :"#{key}="
          if respond_to?(setter)
            public_send(setter, value)
          else
            @metadata[key] = value
          end
        end
      end

      def strict? = @strict == true

      # Create a shallow copy suitable for pipeline branching.
      def dup
        copy = super
        copy.instance_variable_set(:@warnings, @warnings.dup)
        copy.instance_variable_set(:@metadata, @metadata.dup)

        copy.instance_variable_set(:@lore_books, @lore_books.dup)
        copy.instance_variable_set(:@forced_world_info_activations, @forced_world_info_activations.dup)

        copy.instance_variable_set(:@outlets, @outlets.dup)

        pinned_groups_copy = @pinned_groups.transform_values do |value|
          value.is_a?(Array) ? value.dup : value
        end
        copy.instance_variable_set(:@pinned_groups, pinned_groups_copy)

        copy.instance_variable_set(:@blocks, @blocks.dup)
        copy.instance_variable_set(:@continue_blocks, @continue_blocks&.dup)
        copy.instance_variable_set(:@prompt_entries, @prompt_entries&.dup)
        copy.instance_variable_set(:@llm_options, @llm_options&.dup)

        copy.instance_variable_set(:@macro_vars, @macro_vars&.dup)
        copy.instance_variable_set(:@authors_note_overrides, @authors_note_overrides&.dup)

        copy.instance_variable_set(:@scan_messages, @scan_messages&.dup)
        copy.instance_variable_set(:@scan_context, @scan_context&.dup)
        copy.instance_variable_set(:@scan_injects, @scan_injects&.dup)
        copy.instance_variable_set(:@chat_scan_messages, @chat_scan_messages&.dup)
        copy
      end

      # Emit a warning message.
      # In strict mode, raises StrictModeError instead of collecting.
      def warn(message)
        msg = message.to_s

        @warnings << msg
        @instrumenter&.call(:warning, message: msg, stage: @current_stage)

        if @strict
          raise TavernKit::StrictModeError, msg
        end

        effective_warning_handler&.call(msg)

        nil
      end

      # Emit an instrumentation event. No-op when instrumenter is nil.
      #
      # Supports lazy payload evaluation to avoid expensive debug work in
      # production (where instrumenter is typically nil).
      def instrument(event, **payload)
        return nil unless @instrumenter

        if block_given?
          @instrumenter.call(event, **payload.merge(yield))
        else
          @instrumenter.call(event, **payload)
        end
      end

      # Access arbitrary metadata.
      def [](key)
        @metadata[key]
      end

      def []=(key, value)
        @metadata[key] = value
      end

      def key?(key)
        @metadata.key?(key)
      end

      def fetch(key, default = nil, &block)
        @metadata.fetch(key, default, &block)
      end

      # Validate required inputs.
      def validate!
        raise ArgumentError, "character is required" if @character.nil?
        raise ArgumentError, "user is required" if @user.nil?

        self
      end

      private

      def effective_warning_handler
        return default_warning_handler if @warning_handler == :default
        return nil if @warning_handler.nil?

        @warning_handler
      end

      def default_warning_handler
        ->(msg) { $stderr.puts("WARN: #{msg}") }
      end
    end
  end
end
