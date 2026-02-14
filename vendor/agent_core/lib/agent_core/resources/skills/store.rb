# frozen_string_literal: true

module AgentCore
  module Resources
    module Skills
      # Abstract base class for skill storage backends.
      #
      # Implementations can be filesystem-backed, database-backed, etc.
      # The contract supports progressive disclosure: list_skills returns
      # metadata only, load_skill returns the full body.
      class Store
        # List all available skills (metadata only).
        # @return [Array<SkillMetadata>]
        def list_skills
          raise AgentCore::NotImplementedError, "#{self.class}#list_skills must be implemented"
        end

        # Load a skill by name (full body + file index).
        # @param name [String] Skill name
        # @param max_bytes [Integer, nil] Max body size
        # @return [Skill]
        def load_skill(name:, max_bytes: nil)
          raise AgentCore::NotImplementedError, "#{self.class}#load_skill must be implemented"
        end

        # Read a file from within a skill directory.
        # @param name [String] Skill name
        # @param rel_path [String] Relative path within the skill (e.g., "scripts/setup.sh")
        # @param max_bytes [Integer] Max file size
        # @return [String]
        def read_skill_file(name:, rel_path:, max_bytes:)
          raise AgentCore::NotImplementedError, "#{self.class}#read_skill_file must be implemented"
        end
      end
    end
  end
end
