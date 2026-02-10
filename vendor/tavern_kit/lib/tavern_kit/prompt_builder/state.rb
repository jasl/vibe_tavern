# frozen_string_literal: true

module TavernKit
  class PromptBuilder
    # Internal mutable working state that flows through pipeline steps.
    #
    # This object is intentionally step-facing and may contain intermediate
    # data while building the final prompt plan.
    class State
      # Minimal delegate helper (inspired by ActiveSupport::CoreExt::Module#delegate).
      #
      # Kept local to avoid a hard dependency on ActiveSupport.
      def self.delegate(*methods, to:, allow_nil: true)
        methods.each do |method_name|
          define_method(method_name) do |*args, &block|
            target = public_send(to)
            if target.nil?
              return nil if allow_nil

              raise NoMethodError, "undefined method `#{method_name}` for nil:NilClass"
            end

            target.public_send(method_name, *args, &block)
          end
        end
      end

      # ============================================
      # Input data (typically set at initialization)
      # ============================================

      attr_accessor :character
      attr_accessor :user
      attr_accessor :history
      attr_accessor :user_message
      attr_accessor :preset
      attr_accessor :dialect
      attr_accessor :generation_type
      attr_accessor :group
      attr_accessor :lore_books
      attr_accessor :greeting_index
      attr_accessor :authors_note_overrides
      attr_accessor :forced_world_info_activations
      attr_accessor :injection_registry
      attr_accessor :hook_registry
      attr_accessor :macro_vars

      # @return [PromptBuilder::Context, nil] application-owned input context.
      #
      # This object must not be replaced during pipeline execution.
      attr_reader :context

      delegate :type, :id, to: :context, allow_nil: true

      # ============================================
      # Intermediate state (set by steps)
      # ============================================

      attr_accessor :lore_result
      attr_accessor :outlets
      attr_accessor :prompt_entries
      attr_accessor :pinned_groups
      attr_accessor :blocks

      # @return [Object, nil] variables store (VariablesStore::Base)
      #
      # This is application-owned session state; treat it as stable during
      # step execution (do not replace in steps).
      attr_reader :variables_store

      attr_accessor :scan_messages
      attr_accessor :scan_context
      attr_accessor :scan_injects
      attr_accessor :chat_scan_messages
      attr_accessor :default_chat_depth
      attr_accessor :turn_count

      # ============================================
      # Output
      # ============================================

      attr_accessor :plan
      attr_accessor :resolved_greeting
      attr_accessor :resolved_greeting_index
      attr_accessor :trim_report
      attr_accessor :llm_options

      # ============================================
      # Configuration
      # ============================================

      attr_accessor :token_estimator
      attr_accessor :lore_engine
      attr_accessor :expander
      attr_accessor :macro_registry
      attr_accessor :pinned_group_resolver
      attr_accessor :warning_handler
      attr_accessor :strict

      # ============================================
      # Warnings and metadata
      # ============================================

      attr_accessor :instrumenter
      attr_accessor :current_step
      attr_reader :warnings
      attr_reader :metadata

      def initialize(**attrs)
        @warnings = []
        @metadata = {}
        @instrumenter = nil
        @current_step = nil
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

      def context=(value)
        unless value.nil? || value.is_a?(TavernKit::PromptBuilder::Context)
          raise ArgumentError, "context must be a TavernKit::PromptBuilder::Context"
        end

        if !@context.nil? && @context != value && @current_step
          raise ArgumentError, "context cannot be replaced once set"
        end

        @context = value
      end

      def variables_store=(value)
        if !@variables_store.nil? && @variables_store != value && @current_step
          raise ArgumentError, "variables_store cannot be replaced once set"
        end

        @variables_store = value
      end

      # Ensure the state has a variables store.
      #
      # The store is application-owned, session-level state (not per-build),
      # but the pipeline reads/writes it via the State.
      def variables_store!
        @variables_store ||= TavernKit::VariablesStore::InMemory.new
      end

      # Convenience setter for variables store (application injection).
      def set_variable(name, value, scope: :local)
        variables_store!.set(name, value, scope: scope)
        self
      end

      # Convenience multi-set for variables store (application injection).
      def set_variables(hash, scope: :local)
        hash = hash.is_a?(Hash) ? hash : {}
        vars = variables_store!
        hash.each { |k, v| vars.set(k, v, scope: scope) }
        self
      end

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
        @instrumenter&.call(:warning, message: msg, step: @current_step)

        raise TavernKit::StrictModeError, msg if @strict

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
