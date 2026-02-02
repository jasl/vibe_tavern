# frozen_string_literal: true

class CreateCustomersAndOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.integer :tenant_id, null: false
      t.string :name, null: false
      t.string :region, null: false
      t.timestamps
    end

    create_table :orders do |t|
      t.integer :tenant_id, null: false
      t.references :customer, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :status, null: false, default: "placed"
      t.datetime :ordered_at, null: false
      t.timestamps
    end

    add_index :orders, :ordered_at

    return unless connection.adapter_name.to_s.match?(/postg/i)

    %i[customers orders].each do |table|
      execute "ALTER TABLE #{quote_table_name(table)} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{quote_table_name(table)} FORCE ROW LEVEL SECURITY"
      execute <<~SQL.squish
        CREATE POLICY tenant_isolation ON #{quote_table_name(table)}
        USING (tenant_id = current_setting('app.tenant_id', true)::int)
      SQL
    end
  end
end
