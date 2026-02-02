# frozen_string_literal: true

require "json"
require "digest"
require "pathname"

class ReportsController < ApplicationController
  before_action :load_report, only: %i[show edit update run]

  BUILT_IN_REPORTS = [
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

  def index
    ensure_built_in_reports!
    @reports = Report.order(created_at: :desc)
  end

  def show
    assign_run_defaults
    assign_report_source_preview
    assign_flags_docs
    @can_run_isolated_plan = can_run_isolated_plan?
    @runs = recent_runs
  end

  def new
    @report =
      Report.new(
        mode: :source,
        engine: "auto",
        trusted: false,
        allow_imports: false,
        flags_schema: {},
        default_flags: {}
      )

    assign_report_json_fields
  end

  def create
    @report = Report.new(report_params_with_json)
    if @report.save
      redirect_to report_path(@report)
    else
      assign_report_json_fields
      render :new, status: :unprocessable_entity
    end
  rescue JSON::ParserError => e
    @error = e
    assign_report_json_fields
    render :new, status: :unprocessable_entity
  end

  def edit
    assign_report_json_fields
  end

  def update
    if @report.update(report_params_with_json)
      redirect_to report_path(@report)
    else
      assign_report_json_fields
      render :edit, status: :unprocessable_entity
    end
  rescue JSON::ParserError => e
    @error = e
    assign_report_json_fields
    render :edit, status: :unprocessable_entity
  end

  def run
    assign_run_defaults
    assign_report_source_preview
    assign_flags_docs
    @can_run_isolated_plan = can_run_isolated_plan?
    @run_mode = params[:run_mode].presence || "query"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    run_result =
      if @run_mode == "isolated_plan"
        run_isolated_plan!(flags: parse_json_hash!(@flags_json))
      else
        run_query!(flags: parse_json_hash!(@flags_json))
      end

    ReportRun.create!(
      report: @report,
      status: "ok",
      duration_ms: run_result.fetch(:duration_ms),
      row_count: run_result.fetch(:row_count),
      sql_digest: run_result.fetch(:sql_digest),
      functions_used: run_result.fetch(:functions_used),
      relations_used: run_result.fetch(:relations_used),
      created_at: Time.current
    )

    @runs = recent_runs
    render :show
  rescue StandardError => e
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    ReportRun.create!(
      report: @report,
      status: "error",
      duration_ms: duration_ms,
      error_class: e.class.name,
      error_message: e.message,
      created_at: Time.current
    )

    @error = e
    @runs = recent_runs
    render :show, status: :unprocessable_entity
  end

  private

  def assign_run_defaults
    @page = (params[:page].presence || 1).to_i
    @page = 1 if @page < 1

    @per_page = (params[:per_page].presence || Bi::ReportRunner::DEFAULT_PER_PAGE).to_i
    @per_page = Bi::ReportRunner::DEFAULT_PER_PAGE if @per_page < 1
    @per_page = [@per_page, Bi::ReportRunner::MAX_PER_PAGE].min

    @flags_json = params[:flags_json].presence || JSON.pretty_generate(@report.default_flags || {})
    @run_mode = params[:run_mode].presence || "query"
    @refresh = truthy_param?(params[:refresh])
  end

  def assign_report_source_preview
    if @report.mode_file?
      file = @report.file.to_s
      import_root = LogicaRb::Rails.configuration.import_root
      resolved = resolve_logica_file_path(file, import_root: import_root)
      @report_source_label = file
      @report_source = File.exist?(resolved) ? File.binread(resolved) : nil
      @report_source_error = @report_source ? nil : "Missing file: #{file}"
    else
      @report_source_label = "(inline source)"
      @report_source = @report.source.to_s
      @report_source_error = nil
    end
  rescue StandardError => e
    @report_source_label = "(unavailable)"
    @report_source = nil
    @report_source_error = "Could not load source: #{e.class}: #{e.message}"
  end

  def resolve_logica_file_path(file, import_root:)
    file = file.to_s
    return File.expand_path(file) if file.empty?
    return File.expand_path(file) if Pathname.new(file).absolute? || import_root.nil?

    roots = import_root.is_a?(Array) ? import_root : [import_root]
    roots.each do |root|
      next if root.nil? || root.to_s.empty?

      candidate = File.join(root.to_s, file)
      return File.expand_path(candidate) if File.exist?(candidate)
    end

    File.expand_path(File.join(roots.first.to_s, file))
  end

  def assign_flags_docs
    @flags_schema_json = JSON.pretty_generate(@report.flags_schema || {})
    @default_flags_json = JSON.pretty_generate(@report.default_flags || {})
  end

  def recent_runs
    ReportRun.where(report: @report).order(created_at: :desc).limit(20)
  end

  def load_report
    @report = Report.find(params[:id])
  end

  def assign_report_json_fields
    @flags_schema_json = JSON.pretty_generate(@report.flags_schema || {})
    @default_flags_json = JSON.pretty_generate(@report.default_flags || {})
  end

  def report_params
    params.require(:report).permit(
      :name,
      :mode,
      :file,
      :source,
      :predicate,
      :engine,
      :trusted,
      :allow_imports,
      :flags_schema,
      :default_flags
    )
  end

  def report_params_with_json
    p = report_params.to_h
    p[:flags_schema] = parse_json_hash!(p[:flags_schema].presence || "{}")
    p[:default_flags] = parse_json_hash!(p[:default_flags].presence || "{}")
    p
  end

  def parse_json_hash!(text)
    obj = JSON.parse(text.to_s)
    unless obj.is_a?(Hash)
      raise ArgumentError, "JSON must be an object"
    end

    obj
  end

  def can_run_isolated_plan?
    return false unless @report.mode_file? && @report.trusted

    ActiveRecord::Base.connection.adapter_name.to_s.match?(/postg/i)
  end

  def run_query!(flags:)
    runner = Bi::ReportRunner.new(report: @report, flags: flags, page: @page, per_page: @per_page)
    run_result = runner.run!(refresh: @refresh)

    @sql = run_result.sql
    @executed_sql = run_result.executed_sql
    @result = run_result.result
    @cached = run_result.cached
    @functions_used = run_result.functions_used
    @relations_used = run_result.relations_used

    {
      duration_ms: run_result.duration_ms,
      row_count: run_result.row_count,
      sql_digest: run_result.sql_digest,
      functions_used: run_result.functions_used,
      relations_used: run_result.relations_used,
    }
  end

  def run_isolated_plan!(flags:)
    raise ArgumentError, "isolated_plan is only supported for trusted file reports" unless @report.mode_file? && @report.trusted
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    query =
      LogicaRb::Rails.query(
        file: @report.file.to_s,
        predicate: @report.predicate.to_s,
        engine: @report.engine.to_s,
        flags: flags,
        trusted: true,
        allow_imports: !!@report.allow_imports
      )

    @sql = query.sql
    @plan_json = query.plan_json(pretty: true)
    functions_used = Array(query.functions_used)
    relations_used = Array(query.relations_used)

    outputs =
      Bi::IsolatedPlanRunner.new(
        plan_json: @plan_json,
        connection: ActiveRecord::Base.connection,
        page: @page,
        per_page: @per_page
      ).run!

    @result = outputs.fetch(@report.predicate.to_s)
    @executed_sql = nil
    @cached = false
    @functions_used = functions_used
    @relations_used = relations_used

    row_count =
      if @result.respond_to?(:rows)
        @result.rows.length
      else
        Array(@result["rows"]).length
      end

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    {
      duration_ms: duration_ms,
      row_count: row_count,
      sql_digest: Digest::SHA256.hexdigest(@plan_json.to_s),
      functions_used: functions_used,
      relations_used: relations_used,
    }
  end

  def truthy_param?(value)
    v = value.to_s.strip.downcase
    v == "1" || v == "true" || v == "yes" || v == "on"
  end

  def ensure_built_in_reports!
    BUILT_IN_REPORTS.each do |attrs|
      report = Report.find_or_initialize_by(mode: attrs.fetch(:mode), file: attrs[:file], predicate: attrs[:predicate])
      report.assign_attributes(attrs)
      report.save!
    end
  end
end
