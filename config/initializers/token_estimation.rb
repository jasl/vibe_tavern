# frozen_string_literal: true

# Preload tokenizer assets at boot so request hot paths don't pay load cost.
# In production, strict mode should fail fast if any configured tokenizer asset
# is missing or invalid.

require Rails.root.join("lib/agent_core/contrib/token_estimation").to_s

tokenizer_root =
  begin
    Rails.app.creds.option(:token_estimation, :tokenizer_root)
  rescue StandardError
    nil
  end

AgentCore::Contrib::TokenEstimation.configure(
  root: Rails.root,
  tokenizer_root: tokenizer_root,
)

AgentCore::Contrib::TokenEstimation.estimator.preload!(strict: Rails.env.production?)
