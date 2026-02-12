# frozen_string_literal: true

require_relative "test_helper"

require "fileutils"
require "tmpdir"

class SkillsFileSystemStoreTest < Minitest::Test
  def write_skill(root, name:, description: "Test skill", body: "Body")
    skill_dir = File.join(root, name)
    FileUtils.mkdir_p(skill_dir)

    File.write(
      File.join(skill_dir, "SKILL.md"),
      <<~MD,
        ---
        name: #{name}
        description: #{description}
        ---
        #{body}
      MD
    )

    skill_dir
  end

  def test_discovery_and_load_and_file_reads
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      skill_dir = write_skill(skills_root, name: "foo", description: "Foo skill", body: "Hello from foo")

      FileUtils.mkdir_p(File.join(skill_dir, "references"))
      FileUtils.mkdir_p(File.join(skill_dir, "scripts"))
      FileUtils.mkdir_p(File.join(skill_dir, "assets"))

      File.write(File.join(skill_dir, "references", "x.md"), "ref-x")
      File.write(File.join(skill_dir, "scripts", "run.rb"), "puts :ok")
      File.write(File.join(skill_dir, "assets", "a.txt"), "asset-a")

      FileUtils.mkdir_p(File.join(skill_dir, "scripts", "nested"))
      File.write(File.join(skill_dir, "scripts", "nested", "ignored.txt"), "nope")

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)

      metas = store.list_skills
      assert_equal ["foo"], metas.map(&:name)

      meta = metas.first
      assert_equal "Foo skill", meta.description
      assert_equal File.expand_path(skill_dir), meta.location

      skill = store.load_skill(name: "foo")
      assert_equal "foo", skill.meta.name
      assert_equal "Foo skill", skill.meta.description
      assert_includes skill.body_markdown, "Hello from foo"

      assert_equal ["scripts/run.rb"], skill.files_index.fetch(:scripts)
      assert_equal ["references/x.md"], skill.files_index.fetch(:references)
      assert_equal ["assets/a.txt"], skill.files_index.fetch(:assets)

      assert_equal "ref-x", store.read_skill_file(name: "foo", rel_path: "references/x.md")
    end
  end

  def test_read_skill_file_prevents_path_traversal
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      skill_dir = write_skill(skills_root, name: "foo")
      FileUtils.mkdir_p(File.join(skill_dir, "references"))
      File.write(File.join(skill_dir, "references", "x.md"), "ok")

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)

      assert_raises(ArgumentError) { store.read_skill_file(name: "foo", rel_path: "../x") }
      assert_raises(ArgumentError) { store.read_skill_file(name: "foo", rel_path: "references/../x") }
      assert_raises(ArgumentError) { store.read_skill_file(name: "foo", rel_path: "/etc/passwd") }
      assert_raises(ArgumentError) { store.read_skill_file(name: "foo", rel_path: "references/a/b.md") }
    end
  end

  def test_read_skill_file_rejects_symlink_escape
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      outside_dir = File.join(tmp, "outside")
      FileUtils.mkdir_p(outside_dir)
      outside_file = File.join(outside_dir, "secret.md")
      File.write(outside_file, "secret")

      skill_dir = write_skill(skills_root, name: "foo")
      FileUtils.mkdir_p(File.join(skill_dir, "references"))

      link_path = File.join(skill_dir, "references", "secret.md")
      begin
        FileUtils.ln_s(outside_file, link_path)
      rescue NotImplementedError, SystemCallError => e
        skip "symlinks not supported: #{e.class}: #{e.message}"
      end

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)

      error = assert_raises(ArgumentError) { store.read_skill_file(name: "foo", rel_path: "references/secret.md") }
      assert_includes error.message, "Invalid skill file path"
    end
  end

  def test_load_skill_does_not_index_symlinked_directories_outside_skill_dir
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      outside_dir = File.join(tmp, "outside")
      FileUtils.mkdir_p(outside_dir)
      File.write(File.join(outside_dir, "leak.md"), "secret")

      skill_dir = write_skill(skills_root, name: "foo")

      begin
        FileUtils.ln_s(outside_dir, File.join(skill_dir, "references"))
      rescue NotImplementedError, SystemCallError => e
        skip "symlinks not supported: #{e.class}: #{e.message}"
      end

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)
      skill = store.load_skill(name: "foo")

      assert_equal [], skill.files_index.fetch(:references)

      error = assert_raises(ArgumentError) { store.read_skill_file(name: "foo", rel_path: "references/leak.md") }
      assert_includes error.message, "Invalid skill file path"
    end
  end

  def test_list_skills_does_not_use_file_read
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      write_skill(skills_root, name: "foo", description: "Foo skill", body: "Hello")

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)

      original = File.method(:read)
      File.define_singleton_method(:read) { |*| raise "File.read should not be used by list_skills" }

      begin
        metas = store.list_skills
        assert_equal ["foo"], metas.map(&:name)
      ensure
        File.define_singleton_method(:read) { |*args| original.call(*args) }
      end
    end
  end

  def test_list_skills_raises_when_frontmatter_too_large_in_strict_mode
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      skill_dir = File.join(skills_root, "foo")
      FileUtils.mkdir_p(skill_dir)

      max = TavernKit::VibeTavern::Tools::Skills::FileSystemStore::SKILL_MD_FRONTMATTER_MAX_BYTES
      big = "a" * (max + 10)
      File.write(
        File.join(skill_dir, "SKILL.md"),
        <<~MD,
          ---
          name: foo
          description: Foo
          #{big}
          ---
          # Body
        MD
      )

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: true)
      error = assert_raises(ArgumentError) { store.list_skills }
      assert_includes error.message, "frontmatter exceeds"
    end
  end

  def test_list_skills_skips_when_frontmatter_too_large_in_non_strict_mode
    Dir.mktmpdir do |tmp|
      skills_root = File.join(tmp, "skills")
      FileUtils.mkdir_p(skills_root)

      skill_dir = File.join(skills_root, "foo")
      FileUtils.mkdir_p(skill_dir)

      max = TavernKit::VibeTavern::Tools::Skills::FileSystemStore::SKILL_MD_FRONTMATTER_MAX_BYTES
      big = "a" * (max + 10)
      File.write(
        File.join(skill_dir, "SKILL.md"),
        <<~MD,
          ---
          name: foo
          description: Foo
          #{big}
          ---
          # Body
        MD
      )

      store = TavernKit::VibeTavern::Tools::Skills::FileSystemStore.new(dirs: [skills_root], strict: false)
      metas = store.list_skills
      assert_equal [], metas
    end
  end
end
