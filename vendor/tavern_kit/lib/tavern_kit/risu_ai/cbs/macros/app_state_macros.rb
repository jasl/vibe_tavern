# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      module Macros
        module_function

        def resolve_mainprompt(environment)
          text = metadata_string(environment, "mainprompt", "systemprompt")
          text.empty? ? "" : render_nested(text, environment: environment)
        rescue StandardError
          ""
        end
        private_class_method :resolve_mainprompt

        def resolve_jb(environment)
          text = metadata_string(environment, "jb", "jailbreak")
          text.empty? ? "" : render_nested(text, environment: environment)
        rescue StandardError
          ""
        end
        private_class_method :resolve_jb

        def resolve_globalnote(environment)
          text = metadata_string(environment, "globalnote", "systemnote", "ujb")
          text.empty? ? "" : render_nested(text, environment: environment)
        rescue StandardError
          ""
        end
        private_class_method :resolve_globalnote

        def resolve_jbtoggled(environment)
          val = metadata_value(environment, "jbtoggled", "jailbreaktoggle")
          TavernKit::Coerce.bool(val, default: false) ? "1" : "0"
        rescue StandardError
          "0"
        end
        private_class_method :resolve_jbtoggled

        def resolve_maxcontext(environment)
          val = metadata_value(environment, "maxcontext")
          val.nil? ? "" : val.to_s
        rescue StandardError
          ""
        end
        private_class_method :resolve_maxcontext

        def resolve_moduleenabled(args, environment:)
          name = args[0].to_s
          list =
            if environment.respond_to?(:modules)
              Array(environment.modules).map(&:to_s)
            else
              []
            end
          list.include?(name) ? "1" : "0"
        rescue StandardError
          "0"
        end
        private_class_method :resolve_moduleenabled

        def metadata_string(environment, *keys)
          v = metadata_value(environment, *keys)
          v.nil? ? "" : v.to_s
        end
        private_class_method :metadata_string

        def metadata_value(environment, *keys)
          meta = environment.respond_to?(:metadata) ? environment.metadata : nil
          return nil unless meta.is_a?(Hash)

          keys.each do |key|
            k = normalize_name(key)
            return meta[k] if meta.key?(k)
          end

          nil
        end
        private_class_method :metadata_value
      end
    end
  end
end
