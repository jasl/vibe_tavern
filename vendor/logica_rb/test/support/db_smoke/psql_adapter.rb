# frozen_string_literal: true

require "securerandom"

module LogicaRb
  module DbSmoke
    class PsqlAdapter
      SCALAR_ARRAY_ELEM_TYPES = %w[
        bool
        bpchar
        float4
        float8
        int2
        int4
        int8
        numeric
        text
        varchar
      ].freeze

      def self.build(database_url:)
        require "pg"

        conn = PG.connect(database_url)
        schema = "logica_smoke_#{SecureRandom.hex(8)}"
        adapter = new(conn, schema)
        adapter.setup!
        adapter
      rescue LoadError
        nil
      end

      def initialize(conn, schema)
        @conn = conn
        @schema = schema
        @typname_by_oid = {}
        @composite_field_names_by_oid = {}
        @scalar_array_elem_typname_by_oid = {}
        @text_array_decoder = PG::TextDecoder::Array.new(elements_type: PG::TextDecoder::String.new)
        @record_decoder = PG::TextDecoder::Record.new
      end

      attr_reader :conn

      def setup!
        @conn.exec("CREATE SCHEMA #{@schema};")
        @conn.exec("SET search_path TO #{@schema}, public;")
      end

      def exec_script(sql)
        @conn.exec(rewrite_schema(sql.to_s))
      end

      def select_all(sql)
        sql = sql.to_s.strip.sub(/;\s*\z/, "")
        res = @conn.exec(rewrite_schema(sql))
        scalar_array_elem_typnames = scalar_array_elem_typnames_for_result(res)
        typnames = typnames_for_result(res)
        arg_value_composites = arg_value_composites_for_result(res)

        {
          "columns" => res.fields,
          "rows" => res.values.map do |row|
            row.each_with_index.map do |v, idx|
              next "None" if v.nil? || v == "NULL"

              elem_typname = scalar_array_elem_typnames[idx]
              if elem_typname
                normalize_scalar_array(v, elem_typname)
              elsif typnames[idx] == "numeric"
                normalize_pg_numeric_text(v)
              elsif arg_value_composites[idx]
                normalize_arg_value_composite(v)
              else
                v.to_s
              end
            end
          end,
        }
      end

      def close
        @conn.exec("DROP SCHEMA IF EXISTS #{@schema} CASCADE;")
      ensure
        @conn.close if @conn
      end

      private

      def rewrite_schema(sql)
        sql.gsub(/\blogica_home\b/, @schema)
      end

      def scalar_array_elem_typnames_for_result(res)
        res.fields.each_index.map { |idx| scalar_array_elem_typname_for_oid(res.ftype(idx)) }
      end

      def typnames_for_result(res)
        res.fields.each_index.map { |idx| typname_for_oid(res.ftype(idx)) }
      end

      def arg_value_composites_for_result(res)
        res.fields.each_index.map { |idx| arg_value_composite_oid?(res.ftype(idx)) }
      end

      def typname_for_oid(oid)
        oid = Integer(oid)
        return @typname_by_oid[oid] if @typname_by_oid.key?(oid)

        @typname_by_oid[oid] =
          @conn.exec_params("SELECT typname FROM pg_type WHERE oid = $1", [oid]).getvalue(0, 0).to_s
      rescue StandardError
        @typname_by_oid[oid] = nil
      end

      def arg_value_composite_oid?(oid)
        oid = Integer(oid)
        composite_field_names_for_oid(oid) == %w[arg value]
      rescue StandardError
        false
      end

      def composite_field_names_for_oid(oid)
        oid = Integer(oid)
        return @composite_field_names_by_oid[oid] if @composite_field_names_by_oid.key?(oid)

        res =
          @conn.exec_params(
            <<~SQL,
              SELECT a.attname
              FROM pg_type t
              JOIN pg_attribute a ON a.attrelid = t.typrelid
              WHERE t.oid = $1 AND a.attnum > 0 AND NOT a.attisdropped
              ORDER BY a.attnum
            SQL
            [oid]
          )

        @composite_field_names_by_oid[oid] = res.map { |row| row.fetch("attname") }
      rescue StandardError
        @composite_field_names_by_oid[oid] = []
      end

      def scalar_array_elem_typname_for_oid(oid)
        oid = Integer(oid)
        return @scalar_array_elem_typname_by_oid[oid] if @scalar_array_elem_typname_by_oid.key?(oid)

        row =
          @conn.exec_params(
            <<~SQL,
              SELECT elem.typname
              FROM pg_type arr
              JOIN pg_type elem ON elem.oid = arr.typelem
              WHERE arr.oid = $1
            SQL
            [oid]
          ).first

        elem_typname = row && row["typname"]
        elem_typname = elem_typname.to_s
        elem_typname = nil unless SCALAR_ARRAY_ELEM_TYPES.include?(elem_typname)

        @scalar_array_elem_typname_by_oid[oid] = elem_typname
      rescue StandardError
        @scalar_array_elem_typname_by_oid[oid] = nil
      end

      def normalize_scalar_array(value, elem_typname)
        array = @text_array_decoder.decode(value.to_s)
        format_logica_list(array, elem_typname)
      rescue StandardError
        value.to_s
      end

      def format_logica_list(value, elem_typname)
        case value
        when Array
          "[#{value.map { |v| format_logica_list(v, elem_typname) }.join(", ")}]"
        when nil
          "NULL"
        else
          format_logica_list_elem(value, elem_typname)
        end
      end

      def format_logica_list_elem(value, elem_typname)
        str = value.to_s

        case elem_typname
        when "bool"
          return "true" if str == "t" || str == "true"
          return "false" if str == "f" || str == "false"

          str
        when "int2", "int4", "int8", "float4", "float8"
          str.strip
        when "numeric"
          normalize_pg_numeric_text(str)
        else
          "'#{escape_logica_single_quoted(str)}'"
        end
      end

      def escape_logica_single_quoted(str)
        str.gsub("\\", "\\\\").gsub("'", "\\\\'")
      end

      def normalize_arg_value_composite(value)
        parts = @record_decoder.decode(value.to_s)
        return value.to_s unless parts.is_a?(Array) && parts.size == 2

        arg = format_dict_value(parts[0])
        val = format_dict_value(parts[1])
        "{'arg': #{arg}, 'value': #{val}}"
      rescue StandardError
        value.to_s
      end

      def format_dict_value(value)
        return "NULL" if value.nil?

        str = value.to_s
        return "NULL" if str == "NULL"

        if /\A-?\d+(?:\.\d+)?\z/.match?(str)
          normalize_pg_numeric_text(str)
        else
          "'#{escape_logica_single_quoted(str)}'"
        end
      end

      def normalize_pg_numeric_text(value)
        str = value.to_s.strip
        return str unless str.include?(".")

        str = str.sub(/0+\z/, "").sub(/\.\z/, "")
        str = "0" if str == "-0"
        str
      end
    end
  end
end
