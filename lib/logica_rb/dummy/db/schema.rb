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

ActiveRecord::Schema[8.1].define(version: 2025_12_27_000002) do
  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "region", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
  end

  create_table "orders", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "ordered_at", null: false
    t.string "status", default: "placed", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["ordered_at"], name: "index_orders_on_ordered_at"
  end

  create_table "report_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_class"
    t.text "error_message"
    t.json "functions_used", default: [], null: false
    t.json "relations_used", default: [], null: false
    t.integer "report_id", null: false
    t.integer "row_count"
    t.string "sql_digest"
    t.string "status", null: false
    t.index ["created_at"], name: "index_report_runs_on_created_at"
    t.index ["report_id"], name: "index_report_runs_on_report_id"
  end

  create_table "reports", force: :cascade do |t|
    t.boolean "allow_imports", default: false, null: false
    t.datetime "created_at", null: false
    t.json "default_flags", default: {}, null: false
    t.string "engine", default: "auto", null: false
    t.string "file"
    t.json "flags_schema", default: {}, null: false
    t.integer "mode", default: 0, null: false
    t.string "name", null: false
    t.string "predicate", null: false
    t.text "source"
    t.boolean "trusted", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["mode"], name: "index_reports_on_mode"
    t.index ["name"], name: "index_reports_on_name"
  end

  add_foreign_key "orders", "customers"
  add_foreign_key "report_runs", "reports"
end
