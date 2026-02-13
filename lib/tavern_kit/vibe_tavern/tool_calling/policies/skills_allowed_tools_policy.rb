# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module ToolCalling
      module Policies
        class SkillsAllowedToolsPolicy
          DEFAULT_ALLOW_SET_SAMPLE_SIZE = 20

          attr_reader :allow_set, :active_skill_name, :last_change_details

          def initialize(mode:, invalid_allowlist_mode:, available_tool_names:, baseline_tool_names:)
            @mode = normalize_mode(mode)
            @invalid_allowlist_mode = normalize_invalid_allowlist_mode(invalid_allowlist_mode)
            @available_tool_names = normalize_tool_names(available_tool_names)
            @available_tool_name_set = @available_tool_names.each_with_object({}) { |name, out| out[name] = true }
            @baseline_tool_names = normalize_tool_names(baseline_tool_names)

            @allow_set = nil
            @active_skill_name = nil
            @last_change_details = nil
          end

          def mode = @mode
          def invalid_allowlist_mode = @invalid_allowlist_mode

          def active? = !@allow_set.nil?

          def activate!(skill_name:, allowed_tools:, allowed_tools_raw: nil)
            skill_name = skill_name.to_s.strip
            patterns = normalize_patterns(allowed_tools)

            if @mode != :enforce
              deactivate_with_details!(
                skill_name: skill_name,
                allowed_tools_count: patterns.size,
                allowed_tools_raw: allowed_tools_raw,
                reason: "ENFORCEMENT_OFF",
              )
              return
            end

            if patterns.empty?
              deactivate_with_details!(
                skill_name: skill_name,
                allowed_tools_count: 0,
                allowed_tools_raw: allowed_tools_raw,
                reason: "NO_ALLOWED_TOOLS",
              )
              return
            end

            matched = resolve_matches(patterns)
            non_baseline_matches = matched.keys.reject { |name| @baseline_tool_names.include?(name) }

            if non_baseline_matches.empty?
              case @invalid_allowlist_mode
              when :ignore
                deactivate_with_details!(
                  skill_name: skill_name,
                  allowed_tools_count: patterns.size,
                  allowed_tools_raw: allowed_tools_raw,
                  reason: "NO_MATCHES",
                )
                return
              when :enforce
                apply_allow_set!(
                  skill_name: skill_name,
                  allow_set: build_allow_set({}),
                  allowed_tools_count: patterns.size,
                  allowed_tools_raw: allowed_tools_raw,
                  ignored_reason: nil,
                )
                return
              when :error
                raise ArgumentError, "skills.allowed-tools did not match any available tools"
              else
                raise ArgumentError, "Unknown invalid_allowlist_mode: #{@invalid_allowlist_mode.inspect}"
              end
            end

            apply_allow_set!(
              skill_name: skill_name,
              allow_set: build_allow_set(matched),
              allowed_tools_count: patterns.size,
              allowed_tools_raw: allowed_tools_raw,
              ignored_reason: nil,
            )
          end

          def deactivate!
            @allow_set = nil
            @active_skill_name = nil

            @last_change_details = {
              skill_name: nil,
              allowed_tools_count: 0,
              allow_set_count: 0,
              enforced: false,
              ignored_reason: "DEACTIVATED",
              allow_set_sample: [],
            }
          end

          private

          def normalize_mode(value)
            mode = value.to_s.strip
            mode = "off" if mode.empty?
            mode = mode.downcase

            case mode
            when "off"
              :off
            when "enforce"
              :enforce
            else
              raise ArgumentError, "mode must be :off or :enforce"
            end
          end

          def normalize_invalid_allowlist_mode(value)
            mode = value.to_s.strip
            mode = "ignore" if mode.empty?
            mode = mode.downcase

            case mode
            when "ignore"
              :ignore
            when "enforce"
              :enforce
            when "error"
              :error
            else
              raise ArgumentError, "invalid_allowlist_mode must be :ignore, :enforce, or :error"
            end
          end

          def normalize_tool_names(value)
            Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
          end

          def normalize_patterns(value)
            Array(value)
              .map { |v| v.to_s.strip }
              .reject(&:empty?)
              .map { |v| v.tr(".", "_") }
          end

          def resolve_matches(patterns)
            matches = {}

            @available_tool_names.each do |tool_name|
              next unless pattern_list_matches?(patterns, tool_name)

              matches[tool_name] = true
            end

            matches
          end

          def pattern_list_matches?(patterns, tool_name)
            patterns.any? do |pattern|
              if glob_pattern?(pattern)
                File.fnmatch?(pattern, tool_name)
              else
                pattern == tool_name
              end
            end
          rescue StandardError
            false
          end

          def glob_pattern?(pattern)
            pattern.include?("*") || pattern.include?("?") || pattern.include?("[")
          end

          def build_allow_set(matched)
            allow = {}

            @baseline_tool_names.each do |name|
              allow[name] = true if @available_tool_name_set.key?(name) || @available_tool_name_set.empty?
            end

            matched.each_key { |name| allow[name] = true }
            allow
          end

          def apply_allow_set!(skill_name:, allow_set:, allowed_tools_count:, allowed_tools_raw:, ignored_reason:)
            @allow_set = allow_set
            @active_skill_name = skill_name.empty? ? nil : skill_name

            sample = @allow_set.keys.first(DEFAULT_ALLOW_SET_SAMPLE_SIZE)

            @last_change_details = {
              skill_name: skill_name,
              allowed_tools_count: allowed_tools_count,
              allow_set_count: @allow_set.size,
              enforced: true,
              ignored_reason: ignored_reason,
              allow_set_sample: sample,
            }
          end

          def deactivate_with_details!(skill_name:, allowed_tools_count:, allowed_tools_raw:, reason:)
            @allow_set = nil
            @active_skill_name = skill_name.empty? ? nil : skill_name

            @last_change_details = {
              skill_name: skill_name,
              allowed_tools_count: allowed_tools_count,
              allow_set_count: 0,
              enforced: false,
              ignored_reason: reason.to_s,
              allow_set_sample: [],
            }
          end
        end
      end
    end
  end
end
