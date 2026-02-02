# frozen_string_literal: true

namespace :bi do
  desc "Reset DB and seed BI demo data (db:seed:replant)"
  task seed: :environment do
    Rake::Task["db:seed:replant"].invoke
  end

  namespace :seed do
    desc "Reset DB and seed BI demo data with larger defaults (override via BI_*)"
    task large: :environment do
      ENV["BI_SEED"] ||= "42"
      ENV["BI_CUSTOMERS"] ||= "200"
      ENV["BI_ORDERS"] ||= "5000"
      ENV["BI_DAYS"] ||= "180"

      puts "Using large BI seed defaults (override with BI_* env vars)."
      Rake::Task["db:seed:replant"].invoke
    end
  end
end
