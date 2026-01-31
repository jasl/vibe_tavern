# frozen_string_literal: true

module TavernKit
  module RisuAI
    module CBS
      class Environment < TavernKit::Macro::Environment::Base
        attr_reader :chat_index, :message_index

        def self.build(**kwargs)
          new(**kwargs)
        end

        def initialize(character: nil, user: nil, chat_index: nil, message_index: nil, **_kwargs)
          @character = character
          @user = user
          @chat_index = chat_index
          @message_index = message_index
        end

        def character_name = @character&.name.to_s
        def user_name = @user&.name.to_s

        # Stubbed for Wave 5b kickoff; later steps will integrate persisted and
        # ephemeral scopes (local/global/temp/function_arg) without changing Core.
        def get_var(_name, scope: :local) = nil
        def set_var(_name, _value, scope: :local) = nil
        def has_var?(_name, scope: :local) = false
      end
    end
  end
end
