# frozen_string_literal: true

module TavernKit
  module SillyTavern
    module Macro
      class V2Engine < TavernKit::Macro::Engine::Base
        private

        def evaluate_content(text, env, raw_content_hash:, original_once:, context_offset:)
          out = +""
          i = 0
          str = text.to_s

          while i < str.length
            open = str.index("{{", i)
            if open.nil?
              out << str[i..].to_s
              break
            end

            out << str[i...open] if open > i

            close = find_macro_close(str, open)
            if close.nil?
              out << str[open..].to_s
              break
            end

            raw_inner = str[(open + 2)...close].to_s
            raw_original = str[open...(close + 2)].to_s

            value =
              evaluate_macro(
                str,
                open: open,
                close: close,
                raw_inner: raw_inner,
                raw_original: raw_original,
                env: env,
                raw_content_hash: raw_content_hash,
                original_once: original_once,
                context_offset: context_offset,
              )

            out << value[:output]
            i = value[:next_index]
          end

          out
        end

        def evaluate_macro(str, open:, close:, raw_inner:, raw_original:, env:, raw_content_hash:, original_once:, context_offset:)
          inner_start = open + 2
          global_offset = context_offset + open

          variable = evaluate_variable_expr(
            raw_inner,
            env,
            raw_content_hash: raw_content_hash,
            original_once: original_once,
            context_offset: context_offset,
            open: open,
          )
          return { output: variable, next_index: close + 2 } if variable

          info = parse_macro_inner(raw_inner)
          return { output: raw_original, next_index: close + 2 } if info.nil?

          key = info[:key]
          name = info[:name]
          flags = info[:flags]
          arg_spans = info[:args]

          if flags.closing_block?
            return { output: raw_original, next_index: close + 2 }
          end

          # Dynamic macros: only match argless, non-scoped `{{name}}`.
          if arg_spans.empty? && env.respond_to?(:dynamic_macros)
            dyn = env.dynamic_macros
            if dyn.is_a?(Hash)
              dyn_value = lookup_dynamic(dyn, key)
              if dyn_value
                value = dyn_value.respond_to?(:call) ? dyn_value.call : dyn_value
                return { output: normalize_value(value), next_index: close + 2 }
              end
            end
          end

          defn = @registry.respond_to?(:get) ? @registry.get(key) : nil
          can_scope = defn.nil? ? true : defn.accepts_scoped_content?(arg_spans.length)

          if can_scope
            closing = find_matching_closing(str, close + 2, key)
            if closing
              if defn.nil?
                raw = str[open...(closing[:close] + 2)].to_s
                return { output: (@unknown == :empty ? "" : raw), next_index: closing[:close] + 2 }
              end

              scoped_start = close + 2
              scoped_end = closing[:open] - 1
              raw_scoped = scoped_start > scoped_end ? "" : str[scoped_start..scoped_end].to_s
              raw_block = str[open...(closing[:close] + 2)].to_s

              output =
                evaluate_invocation(
                  defn,
                  name,
                  key,
                  raw_inner,
                  flags,
                  arg_spans,
                  raw_scoped,
                  raw_original,
                  env,
                  raw_content_hash: raw_content_hash,
                  original_once: original_once,
                  context_offset: context_offset,
                  inner_start: inner_start,
                  global_offset: global_offset,
                  open: open,
                  close: close,
                  scoped_start: scoped_start,
                  scoped: true,
                  fallback: raw_block,
                )

              return { output: output, next_index: closing[:close] + 2 }
            end
          end

          if defn.nil?
            # Unknown macro: best-effort tolerance.
            return { output: (@unknown == :empty ? "" : raw_original), next_index: close + 2 }
          end

          output =
            evaluate_invocation(
              defn,
              name,
              key,
              raw_inner,
              flags,
              arg_spans,
              nil,
              raw_original,
              env,
              raw_content_hash: raw_content_hash,
              original_once: original_once,
              context_offset: context_offset,
              inner_start: inner_start,
              global_offset: global_offset,
              open: open,
              close: close,
              scoped_start: nil,
              scoped: false,
              fallback: raw_original,
            )

          { output: output, next_index: close + 2 }
        end

        def evaluate_invocation(
          defn,
          name,
          key,
          raw_inner,
          flags,
          arg_spans,
          raw_scoped,
          raw_original,
          env,
          raw_content_hash:,
          original_once:,
          context_offset:,
          inner_start:,
          global_offset:,
          open:,
          close:,
          scoped_start:,
          scoped:,
          fallback:
        )
          delay = defn.respond_to?(:delay_arg_resolution?) && defn.delay_arg_resolution?

          args = []
          raw_args = []

          arg_spans.each do |span|
            raw = span.raw.to_s
            raw_args << raw

            if delay
              args << raw.strip
            else
              arg_offset = context_offset + inner_start + span.start_offset.to_i
              args << evaluate_content(raw, env, raw_content_hash: raw_content_hash, original_once: original_once, context_offset: arg_offset)
            end
          end

          if scoped
            raw_scoped_text = raw_scoped.to_s
            raw_args << raw_scoped_text

            if delay
              args << raw_scoped_text
            else
              scoped_value =
                evaluate_content(
                  raw_scoped_text,
                  env,
                  raw_content_hash: raw_content_hash,
                  original_once: original_once,
                  context_offset: context_offset + scoped_start.to_i,
                )

              scoped_value = trim_scoped_content(scoped_value) unless flags.preserve_whitespace?
              args << scoped_value
            end
          end

          validate_invocation_arity!(defn, args, env: env)
          validate_invocation_arg_types!(defn, args, env: env)

          if key == "original"
            return original_once ? original_once.call : ""
          end

          resolver = lambda do |text, offset_delta: 0|
            evaluate_content(
              text.to_s,
              env,
              raw_content_hash: raw_content_hash,
              original_once: original_once,
              context_offset: global_offset + offset_delta.to_i,
            )
          end

          trimmer = lambda do |content, trim_indent: true|
            trim_scoped_content(content, trim_indent: trim_indent == true)
          end

          warner = lambda do |message|
            env.warn(message) if env.respond_to?(:warn)
          end

          inv = Invocation.new(
            raw_inner: raw_inner.to_s.strip,
            key: key,
            name: key.to_sym,
            args: args,
            raw_args: raw_args,
            flags: flags,
            is_scoped: scoped == true,
            range: { start_offset: open, end_offset: close + 1 },
            offset: global_offset,
            raw_content_hash: raw_content_hash,
            environment: env,
            resolver: resolver,
            trimmer: trimmer,
            warner: warner,
          )

          handler = defn.handler
          value =
            if handler.is_a?(Proc) && handler.arity == 0
              handler.call
            else
              handler.call(inv)
            end

          post_process(env, value, fallback: fallback)
        rescue TavernKit::SillyTavern::MacroError => e
          env.warn(e.message) if env.respond_to?(:warn)
          fallback.to_s
        end

        def post_process(env, value, fallback:)
          if env.respond_to?(:post_process)
            env.post_process.call(value)
          else
            value.to_s
          end
        rescue StandardError
          fallback.to_s
        end
      end
    end
  end
end
