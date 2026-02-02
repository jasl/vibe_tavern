# frozen_string_literal: true

require "set"

require_relative "../common/color"
require_relative "../util"
require_relative "../parser"
require_relative "dialect_libraries/recursion_library"

module LogicaRb
  module Compiler
    module Functors
      class FunctorError < StandardError
        attr_reader :functor_name, :message

        def initialize(message, functor_name)
          super(message)
          @functor_name = functor_name
          @message = message
        end

        def show_message(stream = $stderr)
          stream.puts(LogicaRb::Common::Color.format("{underline}Making{end}:"))
          stream.puts(@functor_name)
          stream.puts(LogicaRb::Common::Color.format("\n[ {error}Error{end} ] ") + @message)
        end
      end

      def self.walk(x, act)
        result = Set.new
        result.merge(Array(act.call(x)))
        if x.is_a?(Array)
          x.each { |v| result.merge(walk(v, act)) }
        elsif x.is_a?(Hash)
          x.each_value { |v| result.merge(walk(v, act)) }
        end
        result
      end

      def self.walk_with_taboo(x, act, taboo)
        result = Set.new
        result.merge(Array(act.call(x)))
        if x.is_a?(Array)
          x.each { |v| result.merge(walk_with_taboo(v, act, taboo)) }
        elsif x.is_a?(Hash)
          x.each do |k, v|
            next if taboo.include?(k)
            result.merge(walk_with_taboo(v, act, taboo))
          end
        end
        result
      end

      class FunctorsEngine
        attr_reader :rules, :extended_rules, :rules_of, :predicates, :direct_args_of

        class NilCounter
          attr_reader :nil_count

          def initialize(proven)
            @proven = proven
            @nil_count = 0
          end

          def count_nils(node)
            if node.is_a?(Hash) && node.key?("predicate_name") && @proven.include?(node["predicate_name"])
              @nil_count += 1
            end
            []
          end
        end

        def initialize(rules)
          @rules = rules
          @extended_rules = LogicaRb::Util.deep_copy(rules)
          @rules_of = LogicaRb::Parser.defined_predicates_rules(rules)
          @predicates = @rules_of.keys.to_set
          @direct_args_of = build_direct_args_of
          @args_of = {}
          @creation_count = 0
          @cached_calls = {}
          @constant_literal_function = {}
          @predicates.each { |p| args_of(p) }
        end

        def get_constant_function(value)
          return @constant_literal_function[value] if @constant_literal_function.key?(value)
          @constant_literal_function[value] = "LogicaCompilerConstant#{@constant_literal_function.length}"
          @constant_literal_function[value]
        end

        def copy_of_args
          @args_of.dup
        end

        def update_structure(new_predicate)
          @rules_of = LogicaRb::Parser.defined_predicates_rules(@extended_rules)
          @predicates = @rules_of.keys.to_set
          @direct_args_of[new_predicate] = build_direct_args_of_predicate(new_predicate) if @rules_of.key?(new_predicate)
          @rules_of.keys.each do |p|
            @direct_args_of[p] ||= build_direct_args_of_predicate(p)
          end

          copied_args_of = copy_of_args
          copied_args_of.each_key do |predicate|
            if predicate == new_predicate || copied_args_of[predicate].include?(new_predicate)
              @args_of.delete(predicate)
            end
          end
          @predicates.each { |p| args_of(p) }
        end

        def parse_make_instruction(predicate, instruction)
          error_message = "Bad functor call (aka @Make instruction):\n#{instruction}"
          if !instruction.key?("1") || !instruction.key?("2")
            raise FunctorError.new(error_message, predicate)
          end
          unless instruction["1"].key?("predicate_name")
            raise FunctorError.new(error_message, predicate)
          end
          applicant = instruction["1"]["predicate_name"]
          args_map = {}
          instruction["2"].each do |arg_name, arg_value_dict|
            if (!arg_value_dict.is_a?(Hash) || !arg_value_dict.key?("predicate_name")) &&
               !arg_value_dict.is_a?(Integer) && !arg_value_dict.is_a?(String)
              raise FunctorError.new(error_message, predicate)
            end
            args_map[arg_name] = if arg_value_dict.is_a?(Hash)
                                   arg_value_dict["predicate_name"]
            else
                                   get_constant_function(arg_value_dict)
            end
          end
          [predicate, applicant, args_map]
        end

        def build_direct_args_of_predicate(functor)
          args = Set.new
          rules = @rules_of[functor] || []
          extract_predicate_name = lambda do |x|
            return [x["predicate_name"]] if x.is_a?(Hash) && x.key?("predicate_name")
            []
          end
          rules.each do |rule|
            if rule.key?("body")
              args.merge(Functors.walk(rule["body"], extract_predicate_name))
            end
            args.merge(Functors.walk(rule["head"]["record"], extract_predicate_name))
          end
          args
        end

        def build_direct_args_of
          direct_args = {}
          @rules_of.each_key do |functor|
            direct_args[functor] = build_direct_args_of_predicate(functor)
          end
          direct_args
        end

        def args_of(functor = nil)
          return @args_of if functor.nil?
          unless @args_of.key?(functor)
            built_args = build_args(functor)
            building_me = "building_#{functor}"
            if built_args.include?(building_me)
              built_args = built_args - [building_me].to_set
            end
            if built_args.any? { |a| a.start_with?("building_") }
              return built_args.reject { |a| a.start_with?("building_") }
            end
            @args_of[functor] = built_args
          end
          @args_of[functor]
        end

        def build_args(functor)
          return Set.new unless @direct_args_of.key?(functor)
          @args_of[functor] = Set.new(["building_#{functor}"])
          result = Set.new
          queue = @direct_args_of[functor].to_a
          until queue.empty?
            e = queue.shift
            result.add(e)
            args_of_e = args_of(e)
            arg_type = args_of_e.is_a?(Set) ? "final" : "preliminary"
            args_of_e.each do |a|
              next if result.include?(a)
              if arg_type == "preliminary"
                queue << a
              else
                result.add(a)
              end
            end
          end
          @args_of.delete(functor)
          result
        end

        def all_rules_of(functor)
          result = []
          return result unless @rules_of.key?(functor)
          result.concat(@rules_of[functor])
          @args_of[functor].each do |f|
            raise FunctorError.new("Failed to eliminate recursion of #{functor}.", functor) if f == functor
            result.concat(@rules_of[f]) if @rules_of.key?(f)
          end
          LogicaRb::Util.deep_copy(result)
        end

        def make(predicate, instruction)
          call_functor(*parse_make_instruction(predicate, instruction))
        end

        def make_all(predicate_to_instruction)
          needs_building = predicate_to_instruction.map { |p, i| parse_make_instruction(p, i)[0] }.to_set
          while needs_building.any?
            something_built = false
            predicate_to_instruction.sort_by(&:first).each do |new_predicate, instruction|
              name, applicant, args_map = parse_make_instruction(new_predicate, instruction)
              next if !needs_building.include?(new_predicate) || needs_building.include?(applicant)
              next if (@args_of[applicant] & needs_building).any?
              next if !(args_map.values.to_set & needs_building).empty?
              make(new_predicate, instruction)
              something_built = true
              needs_building.delete(name)
            end
            if needs_building.any? && !something_built
              raise FunctorError.new("Could not resolve Make order.", needs_building.to_s)
            end
          end
          surviving_rules = remove_rules_proven_to_be_nil(@extended_rules)

          @constant_literal_function.each do |value, function|
            if value.is_a?(Integer)
              @extended_rules << LogicaRb::Parser.parse_rule(LogicaRb::Parser::HeritageAwareString.new("#{function}() = #{value}"))
            elsif value.is_a?(String)
              @extended_rules << LogicaRb::Parser.parse_rule(LogicaRb::Parser::HeritageAwareString.new("#{function}() = \"#{value}\""))
            else
              raise "Unexpected constant literal: #{[value, function]}"
            end
          end
          surviving_rules.each do |p, c|
            if c == 0
              raise FunctorError.new(
                "All rules contain nil for predicate #{p}. Recursion unfolding failed.",
                p
              )
            end
          end
        end

        def collect_annotations(predicates)
          predicates = predicates.to_set
          result = []
          @rules_of.each do |annotation, rules|
            next unless %w[@Limit @OrderBy @Ground @NoInject @Iteration].include?(annotation)
            rules.each do |rule|
              first_fv = rule["head"]["record"]["field_value"][0]["value"]["expression"]
              unless first_fv.dig("literal", "the_predicate")
                raise FunctorError.new("This annotation requires predicate symbol as the first positional argument.", rule["full_text"])
              end
              if predicates.include?(first_fv["literal"]["the_predicate"]["predicate_name"])
                result << rule
              end
            end
          end
          LogicaRb::Util.deep_copy(result)
        end

        def call_key(functor, args_map)
          relevant_args = args_map.select { |k, _v| args_of(functor).include?(k) }
          args = relevant_args.sort.map { |k, v| "#{k}: #{v}" }.join(",")
          "#{functor}(#{args})"
        end

        def call_functor(name, applicant, args_map)
          bad_args = args_map.keys.to_set - args_of(applicant)
          unless bad_args.empty?
            raise FunctorError.new(
              "Functor #{applicant} is applied to arguments #{bad_args.to_a.join(',')}, which it does not have.",
              name
            )
          end
          @creation_count += 1
          rules = all_rules_of(applicant)
          args = args_map.keys.to_set
          rules = rules.select do |r|
            (args & args_of(r["head"]["predicate_name"])).any? || r["head"]["predicate_name"] == applicant
          end
          raise FunctorError.new("Rules for #{applicant} when making #{name} are not found", name) if rules.empty?

          extended_args_map = LogicaRb::Util.deep_copy(args_map)
          rules_to_update = []
          cache_update = {}
          predicates_to_annotate = Set.new
          rules.sort_by(&:to_s).each do |r|
            rule_predicate_name = r["head"]["predicate_name"]
            if rule_predicate_name == applicant
              extended_args_map[rule_predicate_name] = name
              rules_to_update << r
              predicates_to_annotate.add(rule_predicate_name)
            else
              next if args_map.key?(rule_predicate_name)
              call_key_val = call_key(rule_predicate_name, args_map)
              if @cached_calls.key?(call_key_val)
                extended_args_map[rule_predicate_name] = @cached_calls[call_key_val]
              else
                new_predicate_name = "#{rule_predicate_name}_f#{@creation_count}"
                extended_args_map[rule_predicate_name] = new_predicate_name
                cache_update[call_key_val] = new_predicate_name
                rules_to_update << r
                predicates_to_annotate.add(rule_predicate_name)
              end
            end
          end
          rules = rules_to_update
          @cached_calls.merge!(cache_update)
          annotations = collect_annotations(predicates_to_annotate.to_a)
          rules.concat(annotations)
          replace_predicate = lambda do |x|
            if x.is_a?(Hash) && x.key?("predicate_name") && extended_args_map.key?(x["predicate_name"])
              x["predicate_name"] = extended_args_map[x["predicate_name"]]
            end
            []
          end
          Functors.walk(rules, replace_predicate)
          @extended_rules.concat(rules)
          update_structure(name)
        end

        def unfold_recursive_predicate_flat_fashion(cover, depth, rules, iterative, ignition_steps, stop)
          visible = lambda { |p| !p.include?("_MultBodyAggAux") }
          simplified_cover = cover.select { |c| visible.call(c) }.to_set
          direct_args_of = {}
          simplified_cover.each { |c| direct_args_of[c] = [] }
          @direct_args_of.each do |p, args|
            next unless simplified_cover.include?(p)
            args.each do |a|
              next unless cover.include?(a)
              if visible.call(a)
                direct_args_of[p] << a
              else
                @direct_args_of[a].each { |a2| direct_args_of[p] << a2 if cover.include?(a2) }
              end
            end
          end
          replace_predicate = lambda do |original, new_name|
            lambda do |x|
              if x.is_a?(Hash) && x.key?("predicate_name") && x["predicate_name"] == original
                x["predicate_name"] = new_name
              end
              []
            end
          end
          rules.each do |r|
            if cover.include?(r["head"]["predicate_name"])
              p = r["head"]["predicate_name"]
              r["head"]["predicate_name"] = "#{p}_ROne" if visible.call(p)
              simplified_cover.each do |c|
                Functors.walk(r, replace_predicate.call(c, "#{c}_RZero"))
              end
            elsif r["head"]["predicate_name"].start_with?("@") && r["head"]["predicate_name"] != "@Make"
              cover.each { |c| Functors.walk(r, replace_predicate.call(c, "#{c}_ROne")) }
            end
          end
          lib = if iterative
                  DialectLibraries::RecursionLibrary.get_flat_iterative_recursion_functor(depth, simplified_cover.to_a, direct_args_of, ignition_steps, stop)
          else
                  DialectLibraries::RecursionLibrary.get_flat_recursion_functor(depth, simplified_cover.to_a, direct_args_of)
          end
          lib_rules = LogicaRb::Parser.parse_file(lib)["rule"]
          rules.concat(lib_rules)
        end

        def unfold_recursive_predicate(predicate, cover, depth, rules)
          new_predicate_name = "#{predicate}_recursive"
          new_predicate_head_name = "#{predicate}_recursive_head"

          replace_predicate = lambda do |original, new_name|
            lambda do |x|
              if x.is_a?(Hash) && x.key?("predicate_name") && x["predicate_name"] == original
                x["predicate_name"] = new_name
              end
              []
            end
          end

          replacer_of_recursive_predicate = replace_predicate.call(predicate, new_predicate_name)
          replacer_of_recursive_head_predicate = replace_predicate.call(predicate, new_predicate_head_name)

          replacer_of_cover_member = lambda do |member|
            replace_predicate.call(member, "#{member}_recursive_head")
          end

          rules.each do |r|
            if r["head"]["predicate_name"] == predicate
              r["head"]["predicate_name"] = new_predicate_head_name
              Functors.walk(r, replacer_of_recursive_predicate)
              (cover - [predicate]).each { |c| Functors.walk(r, replacer_of_cover_member.call(c)) }
            elsif cover.include?(r["head"]["predicate_name"])
              Functors.walk(r, replacer_of_recursive_predicate)
              (cover - [predicate]).each { |c| Functors.walk(r, replacer_of_cover_member.call(c)) }
            elsif r["head"]["predicate_name"].start_with?("@") && r["head"]["predicate_name"] != "@Make"
              Functors.walk(r, replacer_of_recursive_head_predicate)
              (cover - [predicate]).each { |c| Functors.walk(r, replacer_of_cover_member.call(c)) }
            end
          end

          lib = DialectLibraries::RecursionLibrary.get_recursion_functor(depth)
          lib = lib.gsub("P", predicate)
          lib_rules = LogicaRb::Parser.parse_file(lib)["rule"]
          rules.concat(lib_rules)
          (cover - [predicate]).each do |c|
            rename_lib = DialectLibraries::RecursionLibrary.get_renaming_functor(c, predicate)
            rename_lib_rules = LogicaRb::Parser.parse_file(rename_lib)["rule"]
            rules.concat(rename_lib_rules)
          end
        end

        def get_stop(depth_map, p)
          stop = depth_map.dig(p, "stop")
          stop = stop["predicate_name"] if stop.is_a?(Hash)
          stop
        end

        def unfold_recursions(depth_map, default_iterative, default_depth)
          should_recurse, my_cover = recursive_analysis(depth_map, default_iterative, default_depth)
          new_rules = LogicaRb::Util.deep_copy(@rules)
          should_recurse.each do |p, style|
            depth = depth_map.dig(p, "1") || default_depth
            if style == "vertical"
              unfold_recursive_predicate(p, my_cover[p], depth, new_rules)
            elsif style == "horizontal" || style == "iterative_horizontal"
              ignition = my_cover[p].length + 3
              ignition += 1 if ignition % 2 == depth % 2
              stop = get_stop(depth_map, p)
              if stop && !my_cover[p].include?(stop)
                raise FunctorError.new(
                  LogicaRb::Common::Color.format(
                    "Recursive predicate {warning}{p}{end} uses stop signal {warning}{stop}{end} that does not exist or is outside of the recurvisve component.",
                    { p: p, stop: stop }
                  ),
                  p
                )
              end
              unfold_recursive_predicate_flat_fashion(
                my_cover[p],
                depth,
                new_rules,
                style == "iterative_horizontal",
                depth_map.dig(p, "ignition") || ignition,
                stop
              )
            else
              raise "Unknown recursion style: #{style}"
            end
          end
          new_rules
        end

        def remove_rules_proven_to_be_nil(rules)
          proven = Set.new(["nil"])
          replace_predicate = lambda do |original, new_name|
            lambda do |x|
              if x.is_a?(Hash) && x.key?("predicate_name") && x["predicate_name"] == original
                x["predicate_name"] = new_name
              end
              []
            end
          end
          defined_predicates = rules.map { |r| r["head"]["predicate_name"] }.to_set
          rules_per_predicate = {}
          loop do
            rules_per_predicate = {}
            rules.each do |rule|
              p = rule["head"]["predicate_name"]
              counter = NilCounter.new(proven)
              Functors.walk_with_taboo(rule, counter.method(:count_nils), ["the_predicate", "combine", "satellites"])
              rules_per_predicate[p] = (rules_per_predicate[p] || 0) + (counter.nil_count.zero? ? 1 : 0)
            end
            is_nothing = Set.new
            defined_predicates.each do |p|
              is_nothing.add(p) if rules_per_predicate[p].to_i == 0
            end
            break if is_nothing <= proven
            proven.merge(is_nothing)
          end

          proven.subtract(["nil"]).each do |p|
            rules.each do |rule|
              if rule["head"]["predicate_name"] == p
                rule["head"]["predicate_name"] = "Nullified#{p}"
              elsif !rule["head"]["predicate_name"].start_with?("@")
                Functors.walk(rule, replace_predicate.call(p, "nil"))
              end
            end
            if !p.include?("_")
              raise FunctorError.new(
                LogicaRb::Common::Color.format(
                  "Predicate {warning}{p}{end} was proven to be empty.",
                  { p: p }
                ),
                p
              )
            end
            rules_per_predicate.delete(p)
          end
          update_structure(proven.to_a.last || "")
          rules_per_predicate
        end

        def is_cut_of_cover(p, cover_leaf)
          stack = [[p, Set.new]]
          cover_leaf = cover_leaf.to_set
          until stack.empty?
            t, u = stack.pop
            return false if u.include?(t)
            (cover_leaf & @direct_args_of[t]).each do |x|
              stack << [x, u | [t].to_set] if x != p
            end
          end
          true
        end

        def recursive_analysis(depth_map, default_iterative, default_depth)
          cover = []
          covered = Set.new
          deep = depth_map.keys.to_set
          @args_of.each do |p, args|
            if args.include?(p) && !covered.include?(p) && !p.include?("_MultBodyAggAux")
              c = Set.new([p])
              args.each do |p2|
                c.add(p2) if @args_of.key?(p2) && @args_of[p2].include?(p)
              end
              cover << c
              covered.merge(c)
            end
          end

          my_cover = {}
          cover.each { |c| c.each { |p| my_cover[p] = c } }

          should_recurse = {}
          cover.each do |c|
            p = (c & deep).any? ? (c & deep).min : c.min
            if depth_map.dig(p, "1") == -1
              depth_map[p]["1"] = 1_000_000_000
            end
            depth = depth_map.dig(p, "1") || default_depth
            iterative_flag = depth_map.dig(p, "iterative")
            iterative_default = iterative_flag.nil? ? default_iterative : iterative_flag
            iterative_when_large = (iterative_flag.nil? ? true : iterative_flag) && depth.to_i > 20
            if iterative_default || iterative_when_large
              should_recurse[p] = "iterative_horizontal"
            elsif is_cut_of_cover(p, c)
              should_recurse[p] = "vertical"
            else
              should_recurse[p] = "horizontal"
            end
          end
          [should_recurse, my_cover]
        end
      end
    end
  end
end
