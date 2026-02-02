# frozen_string_literal: true

module LogicaRb
  module Compiler
    module DialectLibraries
      module RecursionLibrary
        module_function

        def get_recursion_functor(depth)
          result_lines = ["P_r0 := P_recursive_head(P_recursive: nil);"]
          depth.times do |i|
            result_lines << "P_r#{i + 1} := P_recursive_head(P_recursive: P_r#{i});"
          end
          result_lines << "P := P_r#{depth}();"
          result_lines.join("\n")
        end

        def get_renaming_functor(member, root)
          "#{member} := #{member}_recursive_head(#{root}_recursive: #{root});"
        end

        def get_flat_recursion_functor(depth, cover, direct_args_of)
          result_rules = []
          cover.sort.each do |p|
            (0..depth).each do |i|
              args = []
              (direct_args_of[p].to_set & cover.to_set).sort.each do |a|
                v = i.zero? ? "nil" : "#{a}_fr#{i - 1}"
                args << "#{a}_RZero: #{v}"
              end
              args_str = args.join(", ")
              result_rules << "#{p}_fr#{i} := #{p}_ROne(#{args_str});"
            end
            result_rules << "#{p} := #{p}_fr#{depth}();"
          end
          result_rules.join("\n")
        end

        def get_flat_iterative_recursion_functor(depth, cover, direct_args_of, ignition_steps, stop)
          result_rules = []
          iterate_over_upper_half = []
          iterate_over_lower_half = []
          inset = 2
          stop_file_name = ""
          if stop
            stop_file_name = "/tmp/logical_stop_#{Time.now.to_f.to_s.delete('.')}_#{stop}.json"
          end

          cover.sort.each do |p|
            (0...ignition_steps).each do |i|
              args = []
              (direct_args_of[p].to_set & cover.to_set).sort.each do |a|
                v = i.zero? ? "nil" : "#{a}_ifr#{i - 1}"
                args << "#{a}_RZero: #{v}"
              end
              args_str = args.join(", ")
              result_rules << "#{p}_ifr#{i} := #{p}_ROne(#{args_str});"
              maybe_copy_to_file = (stop && stop == p) ? ", copy_to_file: \"#{stop_file_name}\"" : ""
              if i != ignition_steps - inset
                result_rules << "@Ground(#{p}_ifr#{i}#{maybe_copy_to_file});"
              else
                result_rules << "@Ground(#{p}_ifr#{i}, #{p}_ifr#{i - 2}#{maybe_copy_to_file});"
              end
            end

            iterate_over_upper_half << "#{p}_ifr#{ignition_steps - inset - 1}"
            iterate_over_lower_half << "#{p}_ifr#{ignition_steps - inset}"
            result_rules << "#{p} := #{p}_ifr#{ignition_steps - 1}();"
          end

          iterate_over = iterate_over_upper_half + iterate_over_lower_half
          iterate_over_str = iterate_over.join(", ")
          maybe_stop = stop ? ", stop_signal: \"#{stop_file_name}\"" : ""
          repetitions = (depth + 1 - ignition_steps) / 2 + 1
          result_rules << "@Iteration(#{cover.min}, predicates: [#{iterate_over_str}], repetitions: #{repetitions}#{maybe_stop});"
          result_rules.join("\n")
        end
      end
    end
  end
end
