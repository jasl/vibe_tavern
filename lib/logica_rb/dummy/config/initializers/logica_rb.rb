# frozen_string_literal: true

require "logica_rb/rails"

LogicaRb::Rails.configure do |c|
  c.import_root = Rails.root.join("app/logica")
  c.cache = true
  c.default_engine = :auto
  c.allowed_import_prefixes = ["datasets"]
  c.access_policy = LogicaRb::AccessPolicy.untrusted(allowed_relations: %w[customers orders])
end
