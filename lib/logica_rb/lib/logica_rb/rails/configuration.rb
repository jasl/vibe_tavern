# frozen_string_literal: true

module LogicaRb
  module Rails
    Configuration = Data.define(
      :import_root,
      :cache,
      :cache_mode,
      :default_engine,
      :allowed_import_prefixes,
      :capabilities,
      :library_profile,
      :untrusted_function_profile,
      :access_policy
    )
  end
end
