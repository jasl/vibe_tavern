# frozen_string_literal: true

require "set"

module LogicaRb
  module DbSmoke
    class ReferencePlanExecutor
      def self.execute!(adapter, plan_hash)
        new(plan_hash).execute!(adapter)
      end

      def initialize(plan_hash)
        @plan = plan_hash
      end

      def execute!(adapter)
        preambles = Array(@plan["preambles"])
        preambles.each do |sql|
          next if sql.to_s.strip.empty?
          adapter.exec_script(sql)
        end

        config = Array(@plan["config"])
        nodes_by_name = config.each_with_object({}) do |node, map|
          map[node["name"]] = node
        end

        iterations = @plan["iterations"] || {}
        member_of_iter = build_member_of_iter(iterations)

        external_deps = build_iteration_external_deps(iterations, nodes_by_name, member_of_iter)

        done_nodes = Set.new
        config.each do |node|
          name = node["name"]
          launcher = node.dig("action", "launcher")
          done_nodes.add(name) if launcher == "none"
        end
        done_iters = Set.new

        loop do
          progressed = false

          config.each do |node|
            name = node["name"]
            next if done_nodes.include?(name)
            next if member_of_iter.key?(name)

            deps = Array(node["requires"])
            next unless deps.all? { |dep| dep_satisfied?(dep, nodes_by_name, member_of_iter, done_nodes, done_iters) }

            exec_node!(adapter, node)
            done_nodes.add(name)
            progressed = true
          end

          next if progressed

          iterations.keys.sort.each do |iter_name|
            next if done_iters.include?(iter_name)

            deps = external_deps.fetch(iter_name)
            next unless deps.all? { |dep| dep_satisfied?(dep, nodes_by_name, member_of_iter, done_nodes, done_iters) }

            run_iteration_group!(adapter, iter_name, iterations.fetch(iter_name), nodes_by_name)
            done_iters.add(iter_name)
            progressed = true
          end

          next if progressed

          all_non_iter_done = config.all? do |node|
            name = node["name"]
            launcher = node.dig("action", "launcher")
            launcher == "none" || done_nodes.include?(name) || member_of_iter.key?(name)
          end
          all_iters_done = done_iters.size == iterations.size

          break if all_non_iter_done && all_iters_done

          raise "Plan execution deadlock/cycle: no ready nodes or iteration groups"
        end

        true
      end

      private

      def build_member_of_iter(iterations)
        member_of_iter = {}
        iterations.each do |iter_name, spec|
          Array(spec["predicates"]).each do |predicate|
            member_of_iter[predicate] = iter_name
          end
        end
        member_of_iter
      end

      def build_iteration_external_deps(iterations, nodes_by_name, member_of_iter)
        iterations.each_with_object({}) do |(iter_name, spec), result|
          members = Array(spec["predicates"])
          members_set = members.to_set

          deps = Set.new
          members.each do |member|
            node = nodes_by_name.fetch(member)
            Array(node["requires"]).each do |dep|
              next if members_set.include?(dep)

              if member_of_iter.key?(dep)
                deps.add("iter:#{member_of_iter.fetch(dep)}")
              else
                deps.add(dep)
              end
            end
          end

          result[iter_name] = deps.to_a.sort
        end
      end

      def dep_satisfied?(dep, nodes_by_name, member_of_iter, done_nodes, done_iters)
        if dep.start_with?("iter:")
          return done_iters.include?(dep.delete_prefix("iter:"))
        end

        node = nodes_by_name.fetch(dep)
        return true if node.dig("action", "launcher") == "none"

        if member_of_iter.key?(dep)
          return done_iters.include?(member_of_iter.fetch(dep))
        end

        done_nodes.include?(dep)
      end

      def exec_node!(adapter, node)
        launcher = node.dig("action", "launcher")
        return if launcher == "none"
        return unless launcher == "query"

        sql = node.dig("action", "sql")
        adapter.exec_script(sql.to_s)
      end

      def run_iteration_group!(adapter, iter_name, spec, nodes_by_name)
        predicates = Array(spec["predicates"])
        repetitions = Integer(spec.fetch("repetitions"))
        stop_signal = spec.fetch("stop_signal").to_s

        repetitions.times do |_round|
          reset_stop_signal!(stop_signal) unless stop_signal.empty?

          predicates.each do |predicate|
            node = nodes_by_name.fetch(predicate)
            exec_node!(adapter, node)
          end

          break if stop_signal_triggered?(stop_signal)
        end
      rescue ArgumentError, TypeError
        raise "Invalid iteration spec for #{iter_name}"
      end

      def reset_stop_signal!(path)
        File.delete(path) if File.exist?(path)
      rescue Errno::ENOENT
        # ignore
      end

      def stop_signal_triggered?(path)
        return false if path.empty?
        return false unless File.exist?(path)

        size = File.size?(path)
        !size.nil? && size.positive?
      rescue Errno::ENOENT
        false
      end
    end
  end
end
