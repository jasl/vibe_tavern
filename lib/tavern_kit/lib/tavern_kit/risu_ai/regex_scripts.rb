# frozen_string_literal: true

module TavernKit
  module RisuAI
    # RisuAI "Regex Scripts" engine.
    #
    # This is a partial implementation intended to match the upstream behavior
    # that Wave 5 characterization tests cover (ordering + move_top/bottom +
    # repeat_back).
    module RegexScripts
      ParsedScript = Data.define(:script, :order, :actions)

      module_function

      def apply(data, scripts, mode:, chat_id: -1, history: nil, role: nil, cbs_conditions: nil, environment: nil)
        # Upstream reference:
        # resources/Risuai/src/ts/process/scripts.ts (processScriptFull)
        value = data.to_s
        base_env = base_environment(environment, chat_id: chat_id, history: history, role: role, cbs_conditions: cbs_conditions)
        value = cbs_parse(value, environment: base_env, chat_id: chat_id, role: role)

        parsed, order_changed = parse_scripts(Array(scripts))
        parsed = parsed.sort_by { |s| -s.order } if order_changed

        parsed.each do |ps|
          script = ps.script
          next if script["in"].to_s.empty?
          next unless script["type"].to_s == mode.to_s

          value = execute_one(
            value,
            script: script,
            actions: ps.actions,
            chat_id: chat_id,
            history: history,
            role: role,
            cbs_conditions: cbs_conditions,
            environment: base_env,
          )
        end

        value
      end

      def parse_scripts(scripts)
        order_changed = false
        parsed = scripts.map do |raw|
          h = TavernKit::Utils.deep_stringify_keys(raw.is_a?(Hash) ? raw : {})

          order = 0
          actions = []
          flag = h["flag"].to_s

          if TavernKit::Coerce.bool(h["ableFlag"], default: false) && flag.include?("<")
            flag = flag.gsub(/<([^>]+)>/) do
              inner = Regexp.last_match(1).to_s
              inner.split(",").each do |part|
                m = part.strip
                next if m.empty?

                if m.start_with?("order ")
                  order = Integer(m.delete_prefix("order ").strip, exception: false) || 0
                  order_changed ||= true
                else
                  actions << m
                end
              end
              ""
            end
          end

          h["flag"] = flag
          ParsedScript.new(script: h, order: order, actions: actions)
        end

        [parsed, order_changed]
      end

      def execute_one(data, script:, actions:, chat_id:, history:, role:, cbs_conditions:, environment:)
        out_script = script["out"].to_s.gsub("$n", "\n")
        out_script = out_script.gsub("{{data}}", "$&")

        flags = resolve_flags(script, out_script: out_script, actions: actions)

        pattern = script["in"].to_s
        pattern = cbs_parse(pattern, environment: environment, chat_id: chat_id, role: role) if actions.include?("cbs")

        regex = compile_regex(pattern, flags: flags, actions: actions)
        return data unless regex

        if out_script.start_with?("@@") || actions.any?
          if regex.match?(data)
            # UI-only directive in upstream: does not modify the message text.
            if out_script.start_with?("@@emo ")
              return data
            end

            # Upstream mutates the underlying chat message when chatID is known.
            # TavernKit stays prompt-building focused, so we only apply the text
            # removal behavior and treat missing chat_id as a no-op (tolerant).
            if out_script.start_with?("@@inject") || actions.include?("inject")
              return data if chat_id == -1

              return replace_data(data, regex, "", global: flags.include?("g"))
            end

            if out_script.start_with?("@@move_top") || out_script.start_with?("@@move_bottom") ||
               actions.include?("move_top") || actions.include?("move_bottom")
              return apply_move(data, regex, out_script: out_script, flags: flags, actions: actions)
            end

            # Default special handling: plain replacement, re-parsed via CBS in upstream.
            replaced = replace_data(data, regex, out_script, global: flags.include?("g"))
            return cbs_parse(replaced, environment: environment, chat_id: chat_id, role: role)
          end

          if (out_script.start_with?("@@repeat_back") || actions.include?("repeat_back")) && chat_id != -1
            return apply_repeat_back(data, regex, out_script: out_script, history: history, role: role)
          end

          return data
        end

        replaced = replace_data(data, regex, out_script, global: flags.include?("g"))
        cbs_parse(replaced, environment: environment, chat_id: chat_id, role: role)
      end

      def resolve_flags(script, out_script:, actions:)
        flag =
          if TavernKit::Coerce.bool(script["ableFlag"], default: false)
            script["flag"].to_s.strip
          else
            "g"
          end

        if out_script.start_with?("@@move_top") || out_script.start_with?("@@move_bottom") ||
           actions.include?("move_top") || actions.include?("move_bottom")
          flag = flag.delete("g")
        end

        if out_script.end_with?(">") && !actions.include?("no_end_nl")
          out_script << "\n"
        end

        flag = flag.strip.gsub(/[^dgimsuvy]/, "")
        flag = flag.chars.uniq.join
        flag = "u" if flag.empty?

        flag
      end

      def compile_regex(pattern, flags:, actions:)
        options = 0
        options |= Regexp::IGNORECASE if flags.include?("i")
        options |= Regexp::MULTILINE if flags.include?("m") || flags.include?("s")

        Regexp.new(pattern, options)
      rescue RegexpError
        nil
      end

      def replace_data(data, regex, out_script, global:)
        if global
          data.gsub(regex) { expand_js_replacement(out_script, Regexp.last_match) }
        else
          data.sub(regex) { expand_js_replacement(out_script, Regexp.last_match) }
        end
      end

      def apply_move(data, regex, out_script:, flags:, actions:)
        global = flags.include?("g")
        matches = []

        if global
          data.scan(regex) { matches << Regexp.last_match }
        else
          m = data.match(regex)
          matches << m if m
        end

        data = replace_data(data, regex, "", global: global)

        matches.each do |m|
          next unless m

          out = out_script.sub(/\A@@move_top\s+/, "").sub(/\A@@move_bottom\s+/, "")
          out = expand_js_replacement(out, m)

          if out_script.start_with?("@@move_top") || actions.include?("move_top")
            data = "#{out}\n#{data}"
          else
            data = "#{data}\n#{out}"
          end
        end

        data
      end

      def apply_repeat_back(data, regex, out_script:, history:, role:)
        pos = out_script.split(" ", 2)[1]

        last = Array(history).reverse.find do |m|
          h = m.is_a?(Hash) ? TavernKit::Utils.deep_stringify_keys(m) : {}
          h["role"].to_s == role.to_s
        end
        return data unless last

        last_data = TavernKit::Utils.deep_stringify_keys(last)["data"].to_s
        match = last_data.match(regex)
        return data unless match

        token = match[0].to_s

        case pos
        when nil
          "#{data}#{token}"
        when "end"
          "#{data}#{token}"
        when "start"
          "#{token}#{data}"
        when "end_nl"
          "#{data}\n#{token}"
        when "start_nl"
          "#{token}\n#{data}"
        else
          data
        end
      end

      def expand_js_replacement(template, match)
        t = template.to_s
        m = match

        t.gsub(/\$(\$|&|\d{1,2})/) do |token|
          case token
          when "$$"
            "$"
          when "$&"
            m[0].to_s
          else
            idx = token.delete_prefix("$").to_i
            m[idx].to_s
          end
        end
      end

      def base_environment(environment, chat_id:, history:, role:, cbs_conditions:)
        return environment if environment

        TavernKit::RisuAI::CBS::Environment.build(
          history: history,
          chat_index: chat_id,
          role: role,
          cbs_conditions: cbs_conditions,
          run_var: false,
          rm_var: false,
        )
      end
      private_class_method :base_environment

      def cbs_parse(text, environment:, chat_id:, role:)
        env =
          if environment.respond_to?(:call_frame)
            environment.call_frame(
              run_var: false,
              rm_var: false,
              chat_index: chat_id,
              role: role,
            )
          else
            environment
          end

        TavernKit::RisuAI::CBS::Engine.new.expand(text.to_s, environment: env)
      end
      private_class_method :cbs_parse
    end
  end
end
