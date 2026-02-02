# frozen_string_literal: true

seed = Integer(ENV.fetch("BI_SEED", "42"))
customers_count = Integer(ENV.fetch("BI_CUSTOMERS", "50"))
orders_count = Integer(ENV.fetch("BI_ORDERS", "600"))
days = Integer(ENV.fetch("BI_DAYS", "90"))
days = 1 if days < 1

regions_env = ENV["BI_REGIONS"].to_s.strip
default_regions = %w[North South East West].freeze
regions =
  if regions_env.empty?
    default_regions
  else
    regions_env.split(/[,\s]+/).map(&:strip).reject(&:empty?).uniq
  end
regions = default_regions if regions.empty?

srand(seed)
rng = Random.new(seed)

puts "BI seed config: BI_SEED=#{seed} BI_CUSTOMERS=#{customers_count} BI_ORDERS=#{orders_count} BI_DAYS=#{days} BI_REGIONS=#{regions.join(",")}"

first_names = %w[
  Alex Casey Chris Dana Eli Finn Harper Jamie Jordan Kai Logan Morgan Quinn Riley Sam Taylor
].freeze
last_names = %w[
  Adams Baker Carter Davis Edwards Flores Garcia Harris Jackson Kim Lopez Miller Nguyen Patel Reed Smith Turner
].freeze
statuses = %w[placed shipped delivered refunded].freeze
tenant_ids = [1, 2].freeze

unless Customer.exists? || Order.exists?
  now = Time.current

  customers =
    customers_count.times.map do
      tenant_id = tenant_ids.sample(random: rng)
      Customer.create!(
        tenant_id: tenant_id,
        name: "#{first_names.sample(random: rng)} #{last_names.sample(random: rng)}",
        region: regions.sample(random: rng),
        created_at: now - rng.rand(0...days).days,
        updated_at: now
      )
    end

  orders_count.times do
    ordered_at = now - rng.rand(0...days).days - rng.rand(0..86_399).seconds
    customer = customers.sample(random: rng)
    Order.create!(
      tenant_id: customer.tenant_id,
      customer: customer,
      amount_cents: rng.rand(500..50_000),
      status: statuses.sample(random: rng),
      ordered_at: ordered_at,
      created_at: ordered_at,
      updated_at: ordered_at
    )
  end

  puts "Seeded #{Customer.count} customers and #{Order.count} orders."
else
  puts "Customer/Order seed data already present, skipping."
end

built_in_reports = [
  {
    name: "Orders by day",
    mode: :file,
    file: "reports/orders_by_day.l",
    predicate: "OrdersByDay",
    engine: "auto",
    trusted: true,
    allow_imports: true,
    flags_schema: {},
    default_flags: {},
  },
  {
    name: "Top customers",
    mode: :file,
    file: "reports/top_customers.l",
    predicate: "TopCustomers",
    engine: "auto",
    trusted: true,
    allow_imports: true,
    flags_schema: {},
    default_flags: {},
  },
  {
    name: "Sales by region",
    mode: :file,
    file: "reports/sales_by_region.l",
    predicate: "SalesByRegion",
    engine: "auto",
    trusted: true,
    allow_imports: true,
    flags_schema: {},
    default_flags: {},
  },
].freeze

built_in_reports.each do |attrs|
  report = Report.find_or_initialize_by(mode: Report.modes.fetch(attrs.fetch(:mode)), file: attrs[:file], predicate: attrs[:predicate])
  report.assign_attributes(attrs)
  report.save!
end

puts "Ensured #{built_in_reports.length} built-in reports."
