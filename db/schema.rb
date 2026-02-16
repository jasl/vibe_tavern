# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_02_16_100300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "continuation_records", force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "consuming_at"
    t.string "continuation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_resume_error_at"
    t.string "last_resume_error_class"
    t.text "last_resume_error_message"
    t.bigint "llm_model_id", null: false
    t.string "parent_continuation_id"
    t.jsonb "payload", null: false
    t.integer "resume_attempts", default: 0, null: false
    t.string "resume_lock_token"
    t.string "run_id", null: false
    t.string "status", default: "current", null: false
    t.string "tooling_key", null: false
    t.datetime "updated_at", null: false
    t.index ["llm_model_id"], name: "index_continuation_records_on_llm_model_id"
    t.index ["run_id", "continuation_id"], name: "index_continuation_records_on_run_id_and_continuation_id", unique: true
    t.index ["run_id", "status"], name: "index_continuation_records_on_run_id_and_status"
    t.index ["run_id"], name: "index_continuation_records_on_run_id", unique: true, where: "((status)::text = 'current'::text)"
    t.index ["status"], name: "index_continuation_records_on_status"
    t.check_constraint "status::text = ANY (ARRAY['current'::character varying, 'consuming'::character varying, 'consumed'::character varying]::text[])", name: "continuation_records_status_check"
  end

  create_table "llm_models", force: :cascade do |t|
    t.text "comment"
    t.datetime "connection_tested_at"
    t.integer "context_window_tokens", default: 0, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.string "key"
    t.bigint "llm_provider_id", null: false
    t.integer "message_overhead_tokens"
    t.string "model", null: false
    t.string "name", null: false
    t.boolean "supports_parallel_tool_calls", default: false, null: false
    t.boolean "supports_response_format_json_object", default: false, null: false
    t.boolean "supports_response_format_json_schema", default: false, null: false
    t.boolean "supports_streaming", default: false, null: false
    t.boolean "supports_tool_calling", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_llm_models_on_key", unique: true
    t.index ["llm_provider_id", "model"], name: "index_llm_models_on_llm_provider_id_and_model", unique: true
    t.index ["llm_provider_id"], name: "index_llm_models_on_llm_provider_id"
    t.check_constraint "context_window_tokens >= 0", name: "llm_models_context_window_tokens_non_negative"
    t.check_constraint "message_overhead_tokens IS NULL OR message_overhead_tokens >= 0", name: "llm_models_message_overhead_tokens_non_negative"
  end

  create_table "llm_presets", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "key"
    t.bigint "llm_model_id", null: false
    t.jsonb "llm_options_overrides", default: {}, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["llm_model_id", "key"], name: "index_llm_presets_on_llm_model_id_and_key", unique: true, where: "(key IS NOT NULL)"
    t.index ["llm_model_id"], name: "index_llm_presets_on_llm_model_id"
  end

  create_table "llm_providers", force: :cascade do |t|
    t.string "api_format", default: "openai", null: false
    t.text "api_key"
    t.string "api_prefix", null: false
    t.string "base_url", null: false
    t.datetime "created_at", null: false
    t.jsonb "headers", default: {}, null: false
    t.jsonb "llm_options_defaults", default: {}, null: false
    t.integer "message_overhead_tokens", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_llm_providers_on_name", unique: true
    t.check_constraint "message_overhead_tokens >= 0", name: "llm_providers_message_overhead_tokens_non_negative"
  end

  create_table "tool_result_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "enqueued_at"
    t.string "executed_name"
    t.datetime "finished_at"
    t.string "locked_by"
    t.string "run_id", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "tool_call_id", null: false
    t.jsonb "tool_result"
    t.datetime "updated_at", null: false
    t.index ["run_id", "tool_call_id"], name: "index_tool_result_records_on_run_id_and_tool_call_id", unique: true
    t.index ["run_id"], name: "index_tool_result_records_on_run_id"
    t.check_constraint "(status::text = 'ready'::text) = (tool_result IS NOT NULL)", name: "tool_result_records_ready_tool_result_check"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'executing'::character varying, 'ready'::character varying]::text[])", name: "tool_result_records_status_check"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "continuation_records", "llm_models"
  add_foreign_key "llm_models", "llm_providers"
  add_foreign_key "llm_presets", "llm_models"
end
