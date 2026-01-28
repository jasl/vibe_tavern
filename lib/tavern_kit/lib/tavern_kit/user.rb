# frozen_string_literal: true

module TavernKit
  # Represents the end-user / persona participating in a chat session.
  #
  # In SillyTavern terms, this maps roughly to "Persona" + a display name.
  # This is an immutable value object (Ruby 3.2+ Data class).
  #
  # Implements the {Participant} interface, allowing it to be used
  # interchangeably with {Character} in chat sessions.
  #
  # @see Participant
  User = Data.define(:name, :persona) do
    include Participant

    def initialize(name:, persona: nil)
      super(name: name, persona: persona)
    end

    # Returns the user's persona text.
    #
    # @return [String] the persona text
    def persona_text
      persona.to_s
    end
  end
end
