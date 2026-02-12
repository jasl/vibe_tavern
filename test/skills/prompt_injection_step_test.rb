# frozen_string_literal: true

require_relative "test_helper"

require "fileutils"
require "tmpdir"

class SkillsPromptInjectionStepTest < Minitest::Test
  def test_pipeline_inserts_available_skills_system_block
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      skill_dir = File.join(skills_root, "foo")
      FileUtils.mkdir_p(skill_dir)

      File.write(
        File.join(skill_dir, "SKILL.md"),
        <<~MD,
          ---
          name: foo
          description: Foo skill
          ---
          Body
        MD
      )

      store =
        TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(
          dirs: [skills_root],
          strict: true,
        )

      context = {
        skills: {
          enabled: true,
          store: store,
          include_location: false,
        },
      }

      runner_config =
        TavernKit::VibeTavern::RunnerConfig.build(
          provider: "openrouter",
          model: "test-model",
          context: context,
        )

      runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
      prompt_request =
        runner.build_request(
          runner_config: runner_config,
          history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        )

      messages = prompt_request.messages
      user_index = messages.rindex { |m| m.is_a?(Hash) && m.fetch(:role, nil).to_s == "user" }
      refute_nil user_index

      skills_index =
        messages.find_index do |m|
          m.is_a?(Hash) &&
            m.fetch(:role, nil).to_s == "system" &&
            m.fetch(:content, "").to_s.include?("<available_skills>")
        end
      refute_nil skills_index

      assert skills_index < user_index

      content = messages.fetch(skills_index).fetch(:content).to_s
      assert_includes content, %(name="foo")
      assert_includes content, %(description="Foo skill")
    end
  end

  def test_pipeline_inserts_available_skills_with_location_when_enabled
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      skill_dir = File.join(skills_root, "foo")
      FileUtils.mkdir_p(skill_dir)

      File.write(
        File.join(skill_dir, "SKILL.md"),
        <<~MD,
          ---
          name: foo
          description: Foo skill
          ---
          Body
        MD
      )

      store =
        TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(
          dirs: [skills_root],
          strict: true,
        )

      context = {
        skills: {
          enabled: true,
          store: store,
          include_location: true,
        },
      }

      runner_config =
        TavernKit::VibeTavern::RunnerConfig.build(
          provider: "openrouter",
          model: "test-model",
          context: context,
        )

      runner = TavernKit::VibeTavern::PromptRunner.new(client: Object.new)
      prompt_request =
        runner.build_request(
          runner_config: runner_config,
          history: [TavernKit::PromptBuilder::Message.new(role: :user, content: "hi")],
        )

      skills_msg =
        prompt_request.messages.find do |m|
          m.is_a?(Hash) &&
            m.fetch(:role, nil).to_s == "system" &&
            m.fetch(:content, "").to_s.include?("<available_skills>")
        end
      refute_nil skills_msg

      content = skills_msg.fetch(:content).to_s
      assert_includes content, %(location="#{File.expand_path(skill_dir)}")
    end
  end
end
