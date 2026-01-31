# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      # Small subset of the CBS macro registry (Wave 5b).
      #
      # Upstream reference:
      # resources/Risuai/src/ts/cbs.ts (registerFunction)
      module Macros
        module_function

        def resolve(name, args, environment:)
          key = normalize_name(name)

          case key
          when "char", "bot"
            resolve_char(environment)
          when "user"
            resolve_user(environment)
          when "prefillsupported", "prefill"
            resolve_prefill_supported(environment)
          when "getvar"
            resolve_getvar(args, environment: environment)
          when "setvar"
            resolve_setvar(args, environment: environment)
          when "addvar"
            resolve_addvar(args, environment: environment)
          when "setdefaultvar"
            resolve_setdefaultvar(args, environment: environment)
          when "getglobalvar"
            resolve_getglobalvar(args, environment: environment)
          when "tempvar", "gettempvar"
            resolve_tempvar(args, environment: environment)
          when "settempvar"
            resolve_settempvar(args, environment: environment)
          when "return"
            resolve_return(args, environment: environment)
          else
            nil
          end
        end

        def normalize_name(name)
          name.to_s.downcase.gsub(/[\s_-]+/, "")
        end
        private_class_method :normalize_name

        def resolve_char(environment)
          char = environment.respond_to?(:character) ? environment.character : nil
          return environment.character_name.to_s if char.nil?

          if char.respond_to?(:display_name)
            char.display_name.to_s
          elsif char.respond_to?(:name)
            char.name.to_s
          else
            environment.character_name.to_s
          end
        end
        private_class_method :resolve_char

        def resolve_user(environment)
          user = environment.respond_to?(:user) ? environment.user : nil
          return environment.user_name.to_s if user.nil?

          user.respond_to?(:name) ? user.name.to_s : environment.user_name.to_s
        end
        private_class_method :resolve_user

        def resolve_prefill_supported(environment)
          # Upstream checks for Claude models (db.aiModel.startsWith('claude')) and
          # returns "1"/"0". TavernKit approximates this using dialect/model_hint.
          dialect = environment.respond_to?(:dialect) ? environment.dialect : nil
          model_hint = environment.respond_to?(:model_hint) ? environment.model_hint.to_s : ""

          supported =
            dialect.to_s == "anthropic" ||
            model_hint.downcase.start_with?("claude") ||
            model_hint.downcase.include?("claude-")

          supported ? "1" : "0"
        end
        private_class_method :resolve_prefill_supported

        def resolve_getvar(args, environment:)
          name = args[0].to_s
          environment.get_var(name, scope: :local).to_s
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_getvar

        def resolve_getglobalvar(args, environment:)
          name = args[0].to_s
          environment.get_var(name, scope: :global).to_s
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_getglobalvar

        def resolve_setvar(args, environment:)
          return "" if rm_var?(environment)
          return nil unless run_var?(environment)

          name = args[0].to_s
          value = args[1].to_s
          environment.set_var(name, value, scope: :local)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_setvar

        def resolve_setdefaultvar(args, environment:)
          return "" if rm_var?(environment)
          return nil unless run_var?(environment)

          name = args[0].to_s
          value = args[1].to_s
          current = environment.get_var(name, scope: :local).to_s
          environment.set_var(name, value, scope: :local) if current.empty?
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_setdefaultvar

        def resolve_addvar(args, environment:)
          return "" if rm_var?(environment)
          return nil unless run_var?(environment)

          name = args[0].to_s
          delta = args[1].to_s

          current = environment.get_var(name, scope: :local).to_s
          sum = current.to_f + delta.to_f
          environment.set_var(name, format_number(sum), scope: :local)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_addvar

        def resolve_tempvar(args, environment:)
          name = args[0].to_s
          environment.get_var(name, scope: :temp).to_s
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_tempvar

        def resolve_settempvar(args, environment:)
          name = args[0].to_s
          value = args[1].to_s
          environment.set_var(name, value, scope: :temp)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_settempvar

        def resolve_return(args, environment:)
          environment.set_var("__return__", args[0], scope: :temp)
          environment.set_var("__force_return__", "1", scope: :temp)
          ""
        rescue NotImplementedError
          ""
        end
        private_class_method :resolve_return

        def run_var?(environment)
          environment.respond_to?(:run_var) && environment.run_var == true
        end
        private_class_method :run_var?

        def rm_var?(environment)
          environment.respond_to?(:rm_var) && environment.rm_var == true
        end
        private_class_method :rm_var?

        def format_number(value)
          v = value.is_a?(Numeric) ? value : value.to_f
          (v.to_f % 1).zero? ? v.to_i.to_s : v.to_f.to_s
        end
        private_class_method :format_number
      end
    end
  end
end
