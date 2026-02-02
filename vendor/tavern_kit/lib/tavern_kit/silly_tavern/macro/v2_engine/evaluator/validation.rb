# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      class V2Engine < TavernKit::Macro::Engine::Base
        private

        def validate_invocation_arity!(defn, args, env:)
          count = Array(args).length
          return if defn.arity_valid?(count)

          list = defn.list_spec
          expected_min = list ? defn.min_args + list.fetch(:min, 0).to_i : defn.min_args
          expected_max =
            if list
              max = list[:max]
              max.nil? ? nil : defn.max_args + max.to_i
            else
              defn.max_args
            end

          expectation =
            if !expected_max.nil? && expected_max != expected_min
              "between #{expected_min} and #{expected_max}"
            elsif !expected_max.nil?
              expected_min.to_s
            else
              "at least #{expected_min}"
            end

          message = %(Macro "#{defn.name}" called with #{count} unnamed arguments but expects #{expectation}.)
          raise TavernKit::SillyTavern::MacroSyntaxError.new(message, macro_name: defn.name) if defn.strict_args?

          env.warn(message) if env.respond_to?(:warn)
        end

        def validate_invocation_arg_types!(defn, args, env:)
          defs = defn.unnamed_arg_defs
          return if defs.empty?

          all_args = Array(args)
          unnamed_count = [all_args.length, defn.max_args].min
          unnamed = all_args.first(unnamed_count)
          return if unnamed.empty?

          count = [defs.length, unnamed.length].min
          count.times do |idx|
            arg_def = defs[idx]
            value = unnamed[idx].to_s

            raw_type =
              if arg_def.is_a?(Hash)
                arg_def[:type] || :string
              else
                :string
              end

            types = Array(raw_type).map { |t| normalize_value_type(t) }.uniq
            next if types.any? { |t| value_of_type?(value, t) }

            arg_name =
              if arg_def.is_a?(Hash)
                arg_def[:name] || "Argument #{idx + 1}"
              else
                "Argument #{idx + 1}"
              end

            optional =
              if arg_def.is_a?(Hash)
                arg_def[:optional]
              else
                false
              end

            optional_label = optional ? " (optional)" : ""
            message =
              %(Macro "#{defn.name}" (position #{idx + 1}#{optional_label}) argument "#{arg_name}" expected type #{raw_type} but got value "#{value}".)

            raise TavernKit::SillyTavern::MacroSyntaxError.new(message, macro_name: defn.name, position: idx + 1) if defn.strict_args?

            env.warn(message) if env.respond_to?(:warn)
          end
        end
      end
    end
  end
end
