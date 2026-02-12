# frozen_string_literal: true

module TavernKit
  module VibeTavern
    module Tools
      module Skills
        # Minimal skills backend contract used by prompt-building and tool calling.
        #
        # Implementations can be filesystem-backed, database-backed, etc.
        class Store
          def list_skills = raise NotImplementedError
          def load_skill(name:) = raise NotImplementedError
          def read_skill_file(name:, rel_path:, max_bytes:) = raise NotImplementedError
        end
      end
    end
  end
end
