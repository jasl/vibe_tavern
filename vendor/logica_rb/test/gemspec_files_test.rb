# frozen_string_literal: true

require "test_helper"

class GemspecFilesTest < Minitest::Test
  def test_gemspec_includes_lib_and_cli_files
    spec = Gem::Specification.load(File.expand_path("../logica_rb.gemspec", __dir__))
    refute_nil spec

    assert_includes spec.files, "README.md"
    assert_includes spec.files, "CHANGELOG.md"
    assert_includes spec.files, "SECURITY.md"
    assert_includes spec.files, "LICENSE.txt"

    assert_includes spec.files, "lib/logica_rb.rb"
    assert_includes spec.files, "lib/logica_rb/version.rb"
    assert_includes spec.files, "exe/logica"
    assert_includes spec.files, "lib/generators/logica_rb/install/install_generator.rb"
    assert_includes spec.files, "lib/generators/logica_rb/install/templates/logica_rb.rb"
    assert_includes spec.files, "docs/security_model.md"

    assert_includes spec.executables, "logica"
  end
end
