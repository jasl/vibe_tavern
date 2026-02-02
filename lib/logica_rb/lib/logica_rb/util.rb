# frozen_string_literal: true

require "json"

module LogicaRb
  module Util
    module_function

    JSON_PRETTY_OPTIONS = {
      indent: " ",
      space: " ",
      space_before: "",
      object_nl: "\n",
      array_nl: "\n",
    }.freeze
    private_constant :JSON_PRETTY_OPTIONS

    def json_dump(obj, pretty: true)
      sorted = sort_keys_recursive(obj)
      return JSON.generate(sorted) + "\n" unless pretty

      JSON.pretty_generate(sorted, **JSON_PRETTY_OPTIONS) + "\n"
    end

    def normalize_optional_string(value)
      return nil if value.nil?

      str =
        if value.respond_to?(:to_path)
          value.to_path
        else
          value.to_s
        end

      str = str.to_s.strip
      return nil if str.empty?

      str
    end

    def join_outputs(outputs)
      trimmed = outputs.map { |text| text.to_s.sub(/\n+\z/, "") }
      trimmed.join("\n\n") + "\n"
    end

    def deep_copy(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[deep_copy(k)] = deep_copy(v) }
      when Array
        obj.map { |v| deep_copy(v) }
      else
        begin
          obj.dup
        rescue TypeError
          obj
        end
      end
    end

    def sort_keys_recursive(obj)
      case obj
      when Hash
        obj.keys.sort_by(&:to_s).each_with_object({}) do |key, h|
          h[key] = sort_keys_recursive(obj[key])
        end
      when Array
        obj.map { |v| sort_keys_recursive(v) }
      else
        obj
      end
    end
  end
end
