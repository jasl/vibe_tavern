# frozen_string_literal: true

require "json"
require "open3"

require_relative "../errors"

module TavernKit
  module VibeTavern
    module Tools
      module MCP
        module Transport
        class Stdio
          attr_accessor :on_stdout_line, :on_stderr_line

          def initialize(command:, args: [], env: {}, chdir: nil, on_stdout_line: nil, on_stderr_line: nil)
            @command = command.to_s
            @args = Array(args).map(&:to_s)
            @env = normalize_env(env)
            @chdir = blank?(chdir) ? nil : chdir.to_s

            @on_stdout_line = on_stdout_line
            @on_stderr_line = on_stderr_line

            @mutex = Mutex.new
            @started = false
            @closed = false

            @stdin = nil
            @stdout = nil
            @stderr = nil
            @wait_thr = nil
            @pid = nil

            @stdout_thread = nil
            @stderr_thread = nil
          end

          def start
            command = @command
            raise ArgumentError, "command is required" if command.strip.empty?

            @mutex.synchronize do
              raise MCP::Errors::ClosedError, "transport is closed" if @closed
              return self if @started

              popen_opts = {}
              popen_opts[:chdir] = @chdir if @chdir

              stdin, stdout, stderr, wait_thr =
                Open3.popen3(@env, command, *@args, **popen_opts)

              @stdin = stdin
              @stdout = stdout
              @stderr = stderr
              @wait_thr = wait_thr
              @pid = wait_thr.pid

              @stdout_thread =
                Thread.new do
                  read_lines(stdout) { |line| safe_call(@on_stdout_line, line) }
                end

              @stderr_thread =
                Thread.new do
                  read_lines(stderr) { |line| safe_call(@on_stderr_line, line) }
                end

              @started = true
            end

            self
          end

          def send_message(hash)
            message = hash.is_a?(Hash) ? hash : {}

            json = JSON.generate(message)
            if json.include?("\n") || json.include?("\r")
              raise ArgumentError, "MCP stdio messages must be newline-delimited JSON (no embedded newlines)"
            end

            stdin = @mutex.synchronize { @stdin }
            raise MCP::Errors::TransportError, "transport is not started" unless stdin

            stdin.write(json)
            stdin.write("\n")
            stdin.flush

            true
          rescue IOError, SystemCallError => e
            raise MCP::Errors::TransportError, "stdio write failed: #{e.class}: #{e.message}"
          end

          def close(timeout_s: 2.0)
            timeout_s = Float(timeout_s)
            raise ArgumentError, "timeout_s must be positive" if timeout_s <= 0

            stdin = nil
            stdout = nil
            stderr = nil
            wait_thr = nil
            pid = nil
            stdout_thread = nil
            stderr_thread = nil

            @mutex.synchronize do
              return nil if @closed

              @closed = true

              stdin = @stdin
              stdout = @stdout
              stderr = @stderr
              wait_thr = @wait_thr
              pid = @pid
              stdout_thread = @stdout_thread
              stderr_thread = @stderr_thread

              @stdin = nil
              @stdout = nil
              @stderr = nil
              @wait_thr = nil
              @pid = nil
              @stdout_thread = nil
              @stderr_thread = nil
            end

            safe_close(stdin)

            if wait_thr && pid
              finished = wait_with_timeout(wait_thr, timeout_s)
              unless finished
                safe_kill("TERM", pid)
                finished = wait_with_timeout(wait_thr, timeout_s)
              end

              unless finished
                safe_kill("KILL", pid)
                wait_with_timeout(wait_thr, timeout_s)
              end
            end

            safe_close(stdout)
            safe_close(stderr)

            stdout_thread&.join(0.2)
            stderr_thread&.join(0.2)

            nil
          rescue ArgumentError, TypeError
            nil
          end

          private

          def read_lines(io, &block)
            io.each_line do |line|
              block.call(line.to_s.chomp)
            end
          rescue IOError, SystemCallError
            nil
          rescue StandardError => e
            safe_call(@on_stderr_line, "stdio reader error: #{e.class}: #{e.message}")
          ensure
            safe_close(io)
          end

          def safe_call(callable, line)
            return unless callable&.respond_to?(:call)

            callable.call(line.to_s)
          rescue StandardError
            nil
          end

          def wait_with_timeout(wait_thr, timeout_s)
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s

            loop do
              return true unless wait_thr.alive?

              now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              return false if now >= deadline

              sleep(0.01)
            end
          rescue StandardError
            false
          end

          def safe_kill(signal, pid)
            Process.kill(signal, pid)
          rescue Errno::ESRCH, Errno::EPERM
            nil
          end

          def safe_close(io)
            return unless io

            io.close unless io.closed?
          rescue IOError, SystemCallError
            nil
          end

          def blank?(value)
            value.nil? || value.to_s.strip.empty?
          end

          def normalize_env(value)
            hash = value.is_a?(Hash) ? value : {}

            hash.each_with_object({}) do |(k, v), out|
              key = k.to_s
              next if key.strip.empty?

              out[key] = v.nil? ? nil : v.to_s
            end
          end
        end
        end
      end
    end
  end
end
