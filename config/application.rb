require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module VibeTavern
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.2

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Disallow permanent checkout of activerecord connections (request scope):
    config.active_record.permanent_connection_checkout = :disallowed

    config.active_record.encryption.primary_key =
      Rails.app.creds.option(:active_record_encryption, :primary_key)
    config.active_record.encryption.deterministic_key =
      Rails.app.creds.option(:active_record_encryption, :deterministic_key)
    config.active_record.encryption.key_derivation_salt =
      Rails.app.creds.option(:active_record_encryption, :key_derivation_salt)

    # Use modern header-based CSRF protection (requires Sec-Fetch-Site header support)
    config.action_controller.forgery_protection_strategy = :header_only

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks rails_ext])

    config.i18n.available_locales = %i[en zh-CN]
    config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml}")]
    # Fallback to English if translation key is missing
    config.i18n.fallbacks = true

    config.generators do |g|
      g.helper false
      g.assets false
    end
  end
end
