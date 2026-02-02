# frozen_string_literal: true

require "easy_talk"

module TavernKit
  class Character
    # Schema for V3 Asset objects.
    #
    # Assets represent embedded resources (images, audio, etc.) in a character card.
    # URI schemes supported by CCv3:
    # - embeded://path/to/asset.png (embedded in CHARX)
    # - ccdefault: (default asset for the type)
    # - __asset:N (legacy PNG chunk reference)
    # - data: (inline data URI)
    # - http(s):// (external URL)
    #
    # @see https://github.com/kwaroran/character-card-spec-v3
    class AssetSchema
      include EasyTalk::Schema

      define_schema do
        title "Character Card Asset"
        description "An embedded or referenced asset in a character card (V3)"

        property :type, String, description: "Asset type (icon, background, user_icon, emotion, or custom x_* type)"
        property :uri, String, description: "Asset URI (embeded://, ccdefault:, __asset:N, data:, or http(s)://)"
        property :name, String, description: "Asset identifier within the character"
        property :ext, String, description: "File extension without dot (e.g., png, jpg, webp)"
      end

      def main_icon?
        type == "icon" && name == "main"
      end

      def main_background?
        type == "background" && name == "main"
      end

      def embedded?
        uri&.start_with?("embeded://")
      end

      def default?
        uri == "ccdefault:"
      end

      def data_uri?
        uri&.start_with?("data:")
      end

      def external_url?
        uri&.match?(%r{\Ahttps?://}i)
      end

      def embedded_path
        return nil unless embedded?

        uri.sub(%r{\Aembeded://}, "")
      end
    end
  end
end
