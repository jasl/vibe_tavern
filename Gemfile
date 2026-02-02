source "https://rubygems.org"

gem "rails", github: "rails/rails"
gem "rails-i18n"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

# Web servers
# Puma is used in development for better ActionCable compatibility
gem "puma", ">= 7.1"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"
# Push notifications
gem "web-push"
# Pagination
gem "geared_pagination"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Use the database-backed adapters for and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

gem "httpx"

gem "js_regex_to_ruby"

gem "easy_talk", path: "lib/easy_talk"
gem "tavern_kit", path: "lib/tavern_kit"
gem "simple_inference", path: "lib/simple_inference"
gem "logica_rb", path: "lib/logica_rb"

# ZIP processing for CharX format
gem "rubyzip", require: "zip"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "dotenv"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "simplecov", require: false

  # Detect N+1 queries
  # gem "bullet"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Mocking and stubbing
  gem "mocha"
end
