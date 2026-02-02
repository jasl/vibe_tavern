# frozen_string_literal: true

require "set"

require_relative "../../common/color"

module LogicaRb
  module TypeInference
    module Research
      module ReferenceAlgebra
        class OpenRecord < Hash
          def to_s
            "{#{super[1..-2]}, ...}"
          end

          def inspect
            to_s
          end
        end

        class ClosedRecord < Hash
          def to_s
            super
          end

          def inspect
            to_s
          end
        end

        class BadType < Array
          def to_s
            a, b = self
            if a.is_a?(Hash) && b.is_a?(Hash)
              if a.is_a?(ClosedRecord)
                a, b = self
              else
                b, a = self
              end
            elsif b == "Singular"
              b, a = self
            end

            colored_t1 = LogicaRb::Common::Color.format("{warning}{t}{end}", { t: ReferenceAlgebra.render_type(a) })
            colored_t2 = LogicaRb::Common::Color.format("{warning}{t}{end}", { t: ReferenceAlgebra.render_type(b) })

            if a.is_a?(ClosedRecord) && b.is_a?(OpenRecord) && !a.key?(b.keys.first)
              colored_e = LogicaRb::Common::Color.format("{warning}{t}{end}", { t: ReferenceAlgebra.render_type(b.keys.first) })
              return "is a record #{colored_t1} and it does not have field #{colored_e}, which is addressed."
            end
            if a == "Singular"
              return "belongs to a list, but is implied to be #{colored_t2}. Logica has to follow existing DB practice (Posgres, BigQuery) and disallow lists to be elements of lists. This includes ArgMaxK and ArgMinK aggregations, as they build lists. Kindly wrap your inner list into a single field record."
            end

            "is implied to be #{colored_t1} and simultaneously #{colored_t2}, which is impossible."
          end

          def inspect
            to_s
          end
        end

        class TypeReference
          attr_accessor :target

          def initialize(target)
            @target = target
          end

          def we_must_go_deeper?
            @target.is_a?(TypeReference)
          end

          def target_value
            result = self
            result = result.target while result.we_must_go_deeper?
            result.target
          end

          def target_type_class_name
            target_value.class.name.split("::").last
          end

          def self.to(target)
            return target if target.is_a?(TypeReference)
            TypeReference.new(target)
          end

          def bad_type?
            target_value.is_a?(BadType)
          end

          def to_s
            "#{@target}@#{object_id.to_s(16)}"
          end

          def inspect
            to_s
          end

          def close_record
            a = self
            a = a.target while a.we_must_go_deeper?
            return if a.target.is_a?(BadType)
            raise a.target.to_s unless a.target.is_a?(Hash)
            a.target = ClosedRecord[a.target]
          end
        end

        module_function

        def str_int_key(x)
          k, _v = x
          return k if k.is_a?(String)
          return format("%03d", k) if k.is_a?(Integer)
          raise "x:#{x}"
        end

        def render_type(t)
          case t
          when String
            t
          when Array
            "[#{render_type(t[0])}]"
          when Hash
            "{#{t.sort_by { |kv| str_int_key(kv) }.map { |k, v| "#{k}: #{render_type(v)}" }.join(', ')}}"
          when BadType
            "(#{render_type(t[0])} != #{render_type(t[1])})"
          else
            raise t.class.name
          end
        end

        def concrete_type(t)
          return t.target_value if t.is_a?(TypeReference)
          t
        end

        def very_concrete_type(t, upward = nil)
          upward ||= Set.new
          return BadType.new(["...", "..."]) if upward.include?(t.object_id)
          upward = upward | [t.object_id].to_set
          c = concrete_type(t)
          if c.is_a?(BadType)
            return BadType.new(c.map { |e| very_concrete_type(e, upward) })
          end
          return c if c.is_a?(String)
          return c.map { |e| very_concrete_type(e, upward) } if c.is_a?(Array)
          if c.is_a?(Hash)
            return c.class[c.transform_values { |v| very_concrete_type(v, upward) }]
          end
          raise c.class.name
        end

        def fully_defined?(t)
          return false if t == "Any" || t == "Singular" || t == "Sequential"
          return true if t.is_a?(String)
          return false if t.is_a?(BadType)
          return fully_defined?(t[0]) if t.is_a?(Array)
          return t.values.all? { |v| fully_defined?(v) } if t.is_a?(Hash)
          false
        end

        def rank(x)
          x = concrete_type(x)
          return -1 if x.is_a?(BadType)
          return 0 if x == "Any"
          return 1 if x == "Singular"
          return 2 if x == "Sequential"
          return 3 if x == "Num"
          return 4 if x == "Str"
          return 5 if x == "Bool"
          return 6 if x == "Time"
          return 7 if x.is_a?(Array)
          return 8 if x.is_a?(OpenRecord)
          return 9 if x.is_a?(ClosedRecord)
          raise "Bad type: #{x}"
        end

        def incompatible(a, b)
          BadType.new([a, b])
        end

        def unify(a, b)
          original_a = a
          original_b = b
          a = a.target while a.we_must_go_deeper?
          b = b.target while b.we_must_go_deeper?
          original_a.target = a if original_a != a
          original_b.target = b if original_b != b
          return if a.object_id == b.object_id
          raise unless a.is_a?(TypeReference) && b.is_a?(TypeReference)

          concrete_a = concrete_type(a)
          concrete_b = concrete_type(b)
          return if concrete_a.is_a?(BadType) || concrete_b.is_a?(BadType)

          if rank(concrete_a) > rank(concrete_b)
            a, b = b, a
            concrete_a, concrete_b = concrete_b, concrete_a
          end

          if concrete_a == "Any"
            a.target = b
            return
          end

          if concrete_a == "Singular"
            if concrete_b.is_a?(Array)
              a.target = incompatible(a.target, b.target)
              b.target = incompatible(b.target, a.target)
              return
            end
            if concrete_b == "Sequential"
              a.target = b
              b.target = "Str"
              return
            end
            a.target = b
            return
          end

          if concrete_a == "Sequential"
            if %w[Str Sequential].include?(concrete_b) || concrete_b.is_a?(Array)
              a.target = b
              return
            end
            a.target = incompatible(a.target, b.target)
            b.target = incompatible(b.target, a.target)
            return
          end

          if %w[Num Str Bool Time].include?(concrete_a)
            if concrete_a == concrete_b
              return
            end
            a.target = incompatible(a.target, b.target)
            b.target = incompatible(b.target, a.target)
            return
          end

          if concrete_a.is_a?(Array)
            if concrete_b.is_a?(Array)
              a_element, b_element = concrete_a + concrete_b
              a_element = TypeReference.to(a_element)
              b_element = TypeReference.to(b_element)
              unify(a_element, b_element)
              if a_element.target_type_class_name == "BadType"
                a.target = incompatible(a.target, b.target)
                b.target = incompatible(b.target, a.target)
                return
              end
              a.target = [a_element]
              b.target = [b_element]
              return
            end
            a.target = incompatible(a.target, b.target)
            b.target = incompatible(b.target, a.target)
            return
          end

          if concrete_a.is_a?(OpenRecord)
            if concrete_b.is_a?(OpenRecord)
              unify_friendly_records(a, b, OpenRecord)
              return
            end
            if concrete_b.is_a?(ClosedRecord)
              if concrete_a.keys.to_set <= concrete_b.keys.to_set
                unify_friendly_records(a, b, ClosedRecord)
                return
              end
              a.target = incompatible(a.target, b.target)
              b.target = incompatible(b.target, a.target)
              return
            end
            raise
          end

          if concrete_a.is_a?(ClosedRecord)
            if concrete_b.is_a?(ClosedRecord)
              if concrete_a.keys.to_set == concrete_b.keys.to_set
                unify_friendly_records(a, b, ClosedRecord)
                return
              end
              a.target = incompatible(a.target, b.target)
              b.target = incompatible(b.target, a.target)
              return
            end
            raise
          end
          raise
        end

        def unify_friendly_records(a, b, record_type)
          concrete_a = concrete_type(a)
          concrete_b = concrete_type(b)
          result = {}
          (concrete_a.keys.to_set | concrete_b.keys.to_set).each do |f|
            x = TypeReference.to("Any")
            unify(x, TypeReference.to(concrete_a[f])) if concrete_a.key?(f)
            unify(x, TypeReference.to(concrete_b[f])) if concrete_b.key?(f)
            if x.target_type_class_name == "BadType"
              a.target = incompatible(a, b)
              b.target = incompatible(b, a)
            end
            result[f] = x
          end
          a.target = TypeReference.new(record_type[result])
          b.target = a.target
        end

        def unify_list_element(a_list, b_element)
          unify(b_element, TypeReference.to("Singular"))
          b = TypeReference.new([b_element])
          unify(a_list, b)
        end

        def unify_record_field(a_record, field_name, b_field_value)
          b = TypeReference.new(OpenRecord[field_name => b_field_value])
          unify(a_record, b)
        end

        class TypeStructureCopier
          def initialize
            @id_to_reference = {}
          end

          def copy_concrete_or_reference_type(t)
            return copy_type_reference(t) if t.is_a?(TypeReference)
            copy_concrete_type(t)
          end

          def copy_concrete_type(t)
            return t if t.is_a?(String)
            return t.map { |e| copy_concrete_or_reference_type(e) } if t.is_a?(Array)
            if t.is_a?(Hash)
              return t.class[t.transform_values { |v| copy_concrete_or_reference_type(v) }]
            end
            if t.is_a?(BadType)
              return BadType.new([copy_concrete_or_reference_type(t[0]), copy_concrete_or_reference_type(t[1])])
            end
            raise
          end

          def copy_type_reference(t)
            unless @id_to_reference.key?(t.object_id)
              target = copy_concrete_or_reference_type(t.target)
              @id_to_reference[t.object_id] = TypeReference.new(target)
            end
            @id_to_reference[t.object_id]
          end
        end

        def revive(t)
          if t.is_a?(String)
            return TypeReference.new(t)
          end
          if t.is_a?(Hash)
            revive_key = lambda do |k|
              return k.to_i if k.match?(/\A\d\z/)
              k
            end
            return TypeReference.new(OpenRecord[t.transform_keys { |k| revive_key.call(k) }.transform_values { |v| revive(v) }])
          end
          if t.is_a?(Array)
            if t.length == 1
              return TypeReference.new(t.map { |e| revive(e) })
            elsif t.length == 2
              return TypeReference.new(BadType.new(t.map { |e| revive(e) }))
            end
            raise t.to_s
          end
          if t.is_a?(BadType)
            return TypeReference.new(BadType.new(t.map { |e| revive(e) }))
          end
          raise "Unknown type: #{t}"
        end
      end
    end
  end
end
