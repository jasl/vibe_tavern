# frozen_string_literal: true

require "json"
require "securerandom"
require "set"

module Bi
  class IsolatedPlanRunner
    MAX_PER_PAGE = 200

    def initialize(plan_hash: nil, plan_json: nil, connection: ActiveRecord::Base.connection, page: nil, per_page: nil)
      @plan_hash =
        if plan_hash
          plan_hash
        elsif plan_json
          JSON.parse(plan_json)
        end

      raise ArgumentError, "plan_hash or plan_json must be provided" unless @plan_hash

      @connection = connection
      @page = (page || 1).to_i
      @page = 1 if @page < 1
      @per_page = per_page.nil? ? nil : per_page.to_i
      @per_page = 1 if @per_page && @per_page < 1
      @per_page = [@per_page, MAX_PER_PAGE].min if @per_page
    end

    def run!
      case @connection.adapter_name.to_s
      when /postg/i
        run_postgres_isolated!
      when /sqlite/i
        run_sqlite_isolated!
      else
        raise ArgumentError, "Unsupported adapter: #{@connection.adapter_name}"
      end
    end

    private

    def run_postgres_isolated!
      schema = "logica_tmp_#{SecureRandom.hex(8)}"
      quoted_schema = @connection.quote_table_name(schema)
      quoted_public = @connection.quote_table_name("public")

      @connection.execute("CREATE SCHEMA #{quoted_schema}")

      outputs = nil
      @connection.transaction(requires_new: true) do
        @connection.execute("SET LOCAL search_path TO #{quoted_schema}, #{quoted_public}")
        adapter = ActiveRecordAdapter.new(@connection)
        PlanExecutor.new(@plan_hash).execute!(adapter)
        outputs = fetch_outputs(adapter)
      end

      outputs
    ensure
      @connection.execute("DROP SCHEMA IF EXISTS #{quoted_schema} CASCADE") if defined?(quoted_schema) && quoted_schema
    end

    def run_sqlite_isolated!
      begin
        require "sqlite3"
      rescue LoadError => e
        raise ArgumentError, "sqlite3 gem is required for sqlite isolation (#{e.message})"
      end

      db = ::SQLite3::Database.new(":memory:")
      db.results_as_hash = false

      adapter = Sqlite3Adapter.new(db)
      PlanExecutor.new(@plan_hash).execute!(adapter)
      fetch_outputs(adapter)
    ensure
      db&.close
    end

    def fetch_outputs(adapter)
      outputs = Array(@plan_hash["outputs"])
      config = Array(@plan_hash["config"])

      outputs.each_with_object({}) do |out, result|
        predicate = out.fetch("predicate", out.fetch("node")).to_s
        node_name = out.fetch("node").to_s
        node = config.find { |n| n["name"].to_s == node_name }
        raise "missing output node in config: #{node_name}" unless node

        sql = node.dig("action", "sql").to_s
        query = sql.strip

        if query.match?(/\A(?:WITH|SELECT)\b/i)
          result[predicate] = adapter.select_all(apply_pagination(query))
        else
          adapter.exec_script(query)
          result[predicate] = nil
        end
      end
    end

    def apply_pagination(query)
      return query unless @per_page

      offset = (@page - 1) * @per_page
      <<~SQL.squish
        SELECT * FROM (#{query}) AS logica_rows
        LIMIT #{Integer(@per_page)} OFFSET #{Integer(offset)}
      SQL
    end

    class ActiveRecordAdapter
      def initialize(connection)
        @connection = connection
      end

      def exec_script(sql)
        @connection.execute(sql)
      end

      def select_all(sql)
        @connection.select_all(sql)
  end
    end

    class Sqlite3Adapter
      def initialize(db)
        @db = db
      end

      def exec_script(sql)
        @db.execute_batch(sql)
      end

      def select_all(sql)
        cols, *rows = @db.execute2(sql)
        { "columns" => cols, "rows" => rows }
      end
    end

    class PlanExecutor
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
