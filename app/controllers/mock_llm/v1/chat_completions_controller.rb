# frozen_string_literal: true

module MockLLM
  module V1
    class ChatCompletionsController < ApplicationController
      include ActionController::Live

      def create
        payload = request.request_parameters

        model = payload["model"].to_s
        messages = normalize_messages(payload["messages"])

        return render_openai_error("model is required", status: :bad_request) if model.blank?
        return render_openai_error("messages must be a non-empty array", status: :bad_request) unless messages.is_a?(Array) && messages.any?

        stream = boolean(payload["stream"])
        include_usage = boolean(payload.dig("stream_options", "include_usage"))

        content = build_mock_content(messages, model: model)
        content = trim_to_max_tokens(content, payload["max_tokens"])

        usage = build_usage(messages, content)

        if stream
          stream_chat_completion(model: model, content: content, usage: usage, include_usage: include_usage)
        else
          render json: build_chat_completion_response(model: model, content: content, usage: usage)
        end
      rescue ActionDispatch::Http::Parameters::ParseError, JSON::ParserError
        render_openai_error("invalid JSON body", status: :bad_request)
      end

      private

      def render_openai_error(message, status:)
        render json: { error: { message: message, type: "invalid_request_error" } }, status: status
      end

      def boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def normalize_messages(raw)
        return raw unless raw.is_a?(Array)

        raw.map do |message|
          if message.is_a?(ActionController::Parameters)
            message.to_unsafe_h
          else
            message
          end
        end
      end

      def build_mock_content(messages, model:)
        last_system =
          messages
            .reverse
            .find { |m| m.is_a?(Hash) && m["role"].to_s == "system" }

        last_user =
          messages
            .reverse
            .find { |m| m.is_a?(Hash) && m["role"].to_s == "user" }

        system_prompt = last_system&.fetch("content", nil).to_s
        prompt = last_user&.fetch("content", nil).to_s.strip
        random_id = "[##{SecureRandom.hex(4)}]"

        if system_prompt.match?(/translation (repair )?engine/i) && prompt.match?(/<textarea/i)
          extracted = prompt.match(/<textarea[^>]*>(.*?)<\/textarea>/m)
          return "<textarea>#{extracted[1]}</textarea> #{random_id}" if extracted
        end

        if prompt.blank?
          "Hello! I'm a mock LLM running inside TavernKit Playground. #{random_id}"
        elsif prompt.match?(/brief greeting/i)
          "Hello! (mock) Nice to meet you. #{random_id}"
        else
          snippet = prompt.gsub(/\s+/, " ").slice(0, 240)
          "Mock response (model=#{model}): #{snippet} #{random_id}"
        end
      end

      def trim_to_max_tokens(content, max_tokens)
        return content if max_tokens.blank?

        tokens = Integer(max_tokens) rescue nil
        return content unless tokens && tokens.positive?

        # Rough heuristic: ~4 chars per token for English-ish text.
        max_chars = tokens * 4
        content.to_s.slice(0, max_chars)
      end

      def build_usage(messages, completion)
        prompt_chars =
          messages.sum do |m|
            next 0 unless m.is_a?(Hash)

            m.fetch("content", "").to_s.length
          end

        completion_chars = completion.to_s.length

        prompt_tokens = (prompt_chars / 4.0).ceil
        completion_tokens = (completion_chars / 4.0).ceil

        {
          "prompt_tokens" => prompt_tokens,
          "completion_tokens" => completion_tokens,
          "total_tokens" => prompt_tokens + completion_tokens,
        }
      end

      def build_chat_completion_response(model:, content:, usage:)
        {
          id: "mockcmpl-#{SecureRandom.hex(12)}",
          object: "chat.completion",
          created: Time.current.to_i,
          model: model,
          choices: [
            {
              index: 0,
              message: { role: "assistant", content: content },
              finish_reason: "stop",
            },
          ],
          usage: usage,
        }
      end

      def stream_chat_completion(model:, content:, usage:, include_usage:)
        response.status = 200
        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        id = "mockcmpl-#{SecureRandom.hex(12)}"
        created = Time.current.to_i
        delay = stream_delay_seconds

        write_sse_event(
          "id" => id,
          "object" => "chat.completion.chunk",
          "created" => created,
          "model" => model,
          "choices" => [
            { "index" => 0, "delta" => { "role" => "assistant" }, "finish_reason" => nil },
          ],
        )

        chunk_strings(content).each do |chunk|
          write_sse_event(
            "id" => id,
            "object" => "chat.completion.chunk",
            "created" => created,
            "model" => model,
            "choices" => [
              { "index" => 0, "delta" => { "content" => chunk }, "finish_reason" => nil },
            ],
          )

          sleep(delay) if delay.positive?
        end

        final_event = {
          "id" => id,
          "object" => "chat.completion.chunk",
          "created" => created,
          "model" => model,
          "choices" => [
            { "index" => 0, "delta" => {}, "finish_reason" => "stop" },
          ],
        }
        final_event["usage"] = usage if include_usage

        write_sse_event(final_event)
        response.stream.write("data: [DONE]\n\n")
      rescue IOError, ActionController::Live::ClientDisconnected
        nil
      ensure
        begin
          response.stream.close
        rescue IOError, ActionController::Live::ClientDisconnected
          nil
        end
      end

      def stream_delay_seconds
        return 0.0 if Rails.env.test?

        raw = ENV.fetch("MOCK_LLM_STREAM_DELAY", "0.02")
        Float(raw)
      rescue ArgumentError, TypeError
        0.0
      end

      def chunk_strings(text)
        text.to_s.scan(/.{1,18}/m)
      end

      def write_sse_event(event_hash)
        response.stream.write("data: #{JSON.generate(event_hash)}\n\n")
      end
    end
  end
end
