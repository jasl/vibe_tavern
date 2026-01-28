# frozen_string_literal: true

require "easy_talk"

module TavernKit
  class Character
    # Schema for arbitrary extension data.
    #
    # Extensions are used to store application-specific data that should
    # be preserved across imports/exports. The CCv3 spec requires that
    # any unknown keys in extensions be preserved.
    #
    # This schema allows any additional properties.
    class ExtensionsSchema
      include EasyTalk::Schema

      define_schema do
        title "Extensions"
        description "Application-specific extension data (preserves unknown keys)"
        additional_properties true
      end
    end
  end
end
