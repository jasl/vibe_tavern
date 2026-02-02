# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"

module LogicaRb
  module DbSmoke
    class SqliteAdapter
      def self.build
        require "sqlite3"
        adapter = new(SQLite3::Database.new(":memory:"))
        adapter.register_functions!
        adapter
      rescue LoadError
        nil
      end

      def initialize(db)
        @db = db
      end

      def exec_script(sql)
        @db.execute_batch(sql.to_s)
      end

      def select_all(sql)
        sql = sql.to_s.strip.sub(/;\s*\z/, "")
        header, *rows = @db.execute2(sql)
        {
          "columns" => Array(header).map(&:to_s),
          "rows" => Array(rows).map do |row|
            Array(row).map { |v| v.nil? || v == "NULL" ? "None" : v.to_s }
          end,
        }
      end

      def close
        @db.close
      end

      def register_functions!
        register_magical_entangle!
        register_in_list!
        register_join_strings!
        register_split!
        register_log!
        register_pow!
        register_floor!
        register_array_concat!
        register_array_concat_agg!
        register_distinct_list_agg!
        register_sort_list!
        register_arg_min_max_aggregates!
        register_fingerprint!
        register_record_helpers!
        register_file_io! if ENV["LOGICA_UNSAFE_IO"] == "1"
      end

      private

      def register_magical_entangle!
        @db.create_function("MagicalEntangle", 2) do |func, a, b|
          func.result =
            if b.nil?
              nil
            elsif b.is_a?(Numeric) ? b.zero? : b.to_s == "0"
              a
            else
              nil
            end
        end
      end

      def register_in_list!
        @db.create_function("IN_LIST", 2) do |func, element, list_json|
          if element.nil? || list_json.nil?
            func.result = nil
            next
          end

          list =
            begin
              JSON.parse(list_json.to_s)
            rescue JSON::ParserError
              []
            end
          list = [] unless list.is_a?(Array)

          func.result = list.include?(element) ? 1 : 0
        end
      end

      def register_join_strings!
        @db.create_function("JOIN_STRINGS", 2) do |func, list_json, delimiter|
          if list_json.nil?
            func.result = nil
            next
          end

          list =
            begin
              JSON.parse(list_json.to_s)
            rescue JSON::ParserError
              []
            end
          list = [list] unless list.is_a?(Array)

          func.result = list.map(&:to_s).join(delimiter.to_s)
        end
      end

      def register_split!
        @db.create_function("SPLIT", 2) do |func, text, delimiter|
          if text.nil?
            func.result = nil
            next
          end

          delim = delimiter.to_s
          parts = text.to_s.split(delim)
          func.result = "[#{parts.map { |p| JSON.generate(p.to_s) }.join(", ")}]"
        end
      end

      def register_log!
        @db.create_function("LOG", 1) do |func, value|
          func.result = value.nil? ? nil : Math.log(value.to_f)
        end
      end

      def register_pow!
        @db.create_function("POW", 2) do |func, x, y|
          if x.nil? || y.nil?
            func.result = nil
            next
          end

          func.result = x.to_f**y.to_f
        end
      end

      def register_floor!
        @db.create_function("FLOOR", 1) do |func, x|
          func.result = x.nil? ? nil : x.to_f.floor.to_f
        end
      end

      def register_array_concat!
        @db.create_function("ARRAY_CONCAT", 2) do |func, a_json, b_json|
          if a_json.nil? || b_json.nil?
            func.result = nil
            next
          end

          a = parse_json_array(a_json)
          b = parse_json_array(b_json)
          func.result = (a && b) ? logica_json_generate(a + b) : nil
        end
      end

      def register_array_concat_agg!
        @db.create_aggregate("ARRAY_CONCAT_AGG", 1) do
          step do |ctx, value_json|
            return if value_json.nil?

            parsed =
              begin
                JSON.parse(value_json.to_s)
              rescue JSON::ParserError
                nil
              end
            return unless parsed.is_a?(Array)

            ctx[:items] ||= []
            ctx[:items].concat(parsed)
          end

          finalize do |ctx|
            ctx.result = LogicaRb::DbSmoke::SqliteAdapter.logica_json_generate(ctx[:items] || [])
          end
        end
      end

      def register_distinct_list_agg!
        @db.create_aggregate("DistinctListAgg", 1) do
          step do |ctx, value|
            return if value.nil?

            ctx[:seen] ||= {}
            ctx[:items] ||= []

            parsed = LogicaRb::DbSmoke::SqliteAdapter.maybe_parse_json_value(value)
            key = JSON.generate(parsed)
            return if ctx[:seen].key?(key)

            ctx[:seen][key] = true
            ctx[:items] << parsed
          end

          finalize do |ctx|
            ctx.result = LogicaRb::DbSmoke::SqliteAdapter.logica_json_generate(ctx[:items] || [])
          end
        end
      end

      def register_sort_list!
        @db.create_function("SortList", 1) do |func, list_json|
          if list_json.nil?
            func.result = nil
            next
          end

          arr = parse_json_array(list_json)
          if arr.nil?
            func.result = nil
            next
          end

          sorted = arr.sort_by do |v|
            if v.nil?
              [0, ""]
            elsif v.is_a?(Numeric)
              [1, v.to_f]
            else
              [2, JSON.generate(v)]
            end
          end

          func.result = logica_json_generate(sorted)
        end
      end

      def register_arg_min_max_aggregates!
        @db.create_aggregate("ArgMin", 3) do
          step do |ctx, payload, order_value, limit|
            ctx[:items] ||= []
            ctx[:index] ||= 0

            if ctx[:limit].nil? && !limit.nil?
              ctx[:limit] = limit.is_a?(Numeric) ? limit.to_i : limit.to_s.to_i
            end

            return if order_value.nil?

            parsed_payload = LogicaRb::DbSmoke::SqliteAdapter.maybe_parse_json_value(payload)
            order_num =
              if order_value.is_a?(Numeric)
                order_value.to_f
              else
                begin
                  Float(order_value.to_s)
                rescue ArgumentError, TypeError
                  order_value.to_s
                end
              end

            ctx[:items] << [order_num, ctx[:index], parsed_payload]
            ctx[:index] += 1
          end

          finalize do |ctx|
            items = ctx[:items] || []
            limit = ctx[:limit]

            if items.empty?
              ctx.result = LogicaRb::DbSmoke::SqliteAdapter.logica_json_generate([])
              next
            end

            is_numeric = items.first[0].is_a?(Numeric)
            sorted =
              if is_numeric
                items.sort_by { |ord, idx, _payload| [ord, idx] }
              else
                items.sort_by { |ord, idx, _payload| [ord.to_s, idx] }
              end

            picked = sorted.map { |_ord, _idx, payload| payload }
            picked = picked.first(limit) if limit && limit.positive?
            ctx.result = LogicaRb::DbSmoke::SqliteAdapter.logica_json_generate(picked)
          end
        end

        @db.create_aggregate("ArgMax", 3) do
          step do |ctx, payload, order_value, limit|
            ctx[:items] ||= []
            ctx[:index] ||= 0

            if ctx[:limit].nil? && !limit.nil?
              ctx[:limit] = limit.is_a?(Numeric) ? limit.to_i : limit.to_s.to_i
            end

            return if order_value.nil?

            parsed_payload = LogicaRb::DbSmoke::SqliteAdapter.maybe_parse_json_value(payload)
            order_num =
              if order_value.is_a?(Numeric)
                order_value.to_f
              else
                begin
                  Float(order_value.to_s)
                rescue ArgumentError, TypeError
                  order_value.to_s
                end
              end

            ctx[:items] << [order_num, ctx[:index], parsed_payload]
            ctx[:index] += 1
          end

          finalize do |ctx|
            items = ctx[:items] || []
            limit = ctx[:limit]

            if items.empty?
              ctx.result = LogicaRb::DbSmoke::SqliteAdapter.logica_json_generate([])
              next
            end

            is_numeric = items.first[0].is_a?(Numeric)
            sorted =
              if is_numeric
                items.sort_by { |ord, idx, _payload| [-ord, idx] }
              else
                items.sort_by { |ord, idx, _payload| [ord.to_s, idx] }.reverse
              end

            picked = sorted.map { |_ord, _idx, payload| payload }
            picked = picked.first(limit) if limit && limit.positive?
            ctx.result = LogicaRb::DbSmoke::SqliteAdapter.logica_json_generate(picked)
          end
        end
      end

      def register_fingerprint!
        @db.create_function("Fingerprint", 1) do |func, value|
          if value.nil?
            func.result = nil
            next
          end

          input =
            if value.is_a?(Numeric)
              [value.to_i].pack("q<")
            else
              value.to_s
            end

          bytes = Digest::SHA512.digest(input)
          func.result = bytes.byteslice(52, 8).unpack1("q<")
        end
      end

      def register_record_helpers!
        @db.create_function("AssembleRecord", 1) do |func, field_values_json|
          arr =
            begin
              JSON.parse(field_values_json.to_s)
            rescue JSON::ParserError
              []
            end
          arr = [] unless arr.is_a?(Array)

          record = {}
          arr.each do |entry|
            next unless entry.is_a?(Hash)
            key = entry["arg"]
            next unless key.is_a?(String)
            record[key] = entry["value"]
          end

          func.result = logica_json_generate(record)
        end

        @db.create_function("DisassembleRecord", 1) do |func, record_json|
          record =
            begin
              JSON.parse(record_json.to_s)
            rescue JSON::ParserError
              {}
            end
          record = {} unless record.is_a?(Hash)

          arr = record.map { |k, v| { "arg" => k.to_s, "value" => v } }
          func.result = logica_json_generate(arr)
        end
      end

      def register_file_io!
        @db.create_function("ReadFile", 1) do |func, filename|
          path = safe_tmp_path!(filename.to_s)
          func.result = File.binread(path)
        end

        @db.create_function("WriteFile", 2) do |func, filename, content|
          path = safe_tmp_path!(filename.to_s)
          File.binwrite(path, content.to_s)
          func.result = "OK"
        end
      end

      def safe_tmp_path!(filename)
        name = filename.to_s
        raise ArgumentError, "filename must be provided" if name.empty?

        expanded = File.expand_path(name)
        dir_real = File.realpath(File.dirname(expanded))

        allowed_roots = [Dir.tmpdir, "/tmp", "/private/tmp"].uniq
        allowed_real_roots = allowed_roots.filter_map { |r| File.realpath(r) rescue nil }.uniq

        unless allowed_real_roots.any? { |root| dir_real == root || dir_real.start_with?("#{root}#{File::SEPARATOR}") }
          raise ArgumentError, "unsafe path for file IO: #{expanded}"
        end

        expanded
      end

      def parse_json_array(value)
        parsed =
          begin
            JSON.parse(value.to_s)
          rescue JSON::ParserError
            nil
          end

        return nil unless parsed.is_a?(Array)
        parsed
      end

      def logica_json_generate(value)
        self.class.logica_json_generate(value)
      end

      def self.maybe_parse_json_value(value)
        value
      end

      def self.logica_json_generate(value)
        case value
        when Hash
          inner =
            value.map do |k, v|
              "#{JSON.generate(k.to_s)}: #{logica_json_generate(v)}"
            end.join(", ")

          "{#{inner}}"
        when Array
          "[#{value.map { |v| logica_json_generate(v) }.join(", ")}]"
        else
          JSON.generate(value)
        end
      end
    end
  end
end
