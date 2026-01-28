# frozen_string_literal: true

module TavernKit
  # Interface for chat participants (users, characters acting as users, etc.).
  #
  # Any object that includes {Participant} and implements #name and #persona_text
  # can be used as a participant in a chat session. This enables pure AI
  # conversations where a Character card can act as the "user" role.
  #
  # @example Using a Character as User
  #   alice = TavernKit::CharacterCard.load("alice.png")
  #   bob = TavernKit::CharacterCard.load("bob.png")
  #
  #   # Alice is the assistant, Bob acts as the user
  #   plan = TavernKit.build(pipeline: TavernKit::SillyTavern::Pipeline) do
  #     character alice
  #     user bob  # Character acts as user!
  #     message "Hello!"
  #   end
  #
  # @example Traditional user
  #   user = TavernKit::User.new(name: "Alice", persona: "A curious adventurer")
  #   plan = TavernKit.build(pipeline: TavernKit::SillyTavern::Pipeline) do
  #     character character
  #     user user
  #     message "Hello!"
  #   end
  #
  module Participant
    # Returns the participant's display name.
    #
    # @return [String] the display name
    # @abstract
    def name
      raise NotImplementedError, "#{self.class} must implement #name"
    end

    # Returns the participant's persona/description text.
    #
    # For User, this is the persona field.
    # For Character, this combines description and personality fields.
    #
    # @return [String] the persona text
    # @abstract
    def persona_text
      raise NotImplementedError, "#{self.class} must implement #persona_text"
    end
  end
end
