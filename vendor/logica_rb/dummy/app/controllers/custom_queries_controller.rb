# frozen_string_literal: true

require "json"

class CustomQueriesController < ApplicationController
  def new
    @predicate = (params[:predicate].presence || "CustomReport").to_s
    @source = (params[:source].presence || default_source_for(@predicate)).to_s
    @flags_json = (params[:flags_json].presence || "{}").to_s
    @page = (params[:page].presence || 1).to_i
    @page = 1 if @page < 1
    @per_page = (params[:per_page].presence || Bi::ReportRunner::DEFAULT_PER_PAGE).to_i
    @per_page = Bi::ReportRunner::DEFAULT_PER_PAGE if @per_page < 1
    @per_page = [@per_page, Bi::ReportRunner::MAX_PER_PAGE].min
    @allow_imports = params[:allow_imports] == "1"
    @name = (params[:name].presence || "").to_s
  end

  def create
    @predicate = params[:predicate].to_s
    @source = params[:source].to_s
    @flags_json = (params[:flags_json].presence || "{}").to_s
    @page = (params[:page].presence || 1).to_i
    @page = 1 if @page < 1
    @per_page = (params[:per_page].presence || Bi::ReportRunner::DEFAULT_PER_PAGE).to_i
    @per_page = Bi::ReportRunner::DEFAULT_PER_PAGE if @per_page < 1
    @per_page = [@per_page, Bi::ReportRunner::MAX_PER_PAGE].min
    @allow_imports = params[:allow_imports] == "1"
    @name = (params[:name].presence || "").to_s

    intent = params[:intent].to_s

    if intent == "save"
      report =
        Report.new(
          name: @name.presence || "Untitled report",
          mode: :source,
          source: @source,
          predicate: @predicate,
          engine: "auto",
          trusted: false,
          allow_imports: @allow_imports,
          flags_schema: nil,
          default_flags: parse_json_hash!(@flags_json)
        )

      if report.save
        redirect_to report_path(report)
      else
        @error = report.errors.full_messages.join(", ")
        render :new, status: :unprocessable_entity
      end
      return
    end

    report_spec =
      Bi::ReportRunner::ReportSpec.new(
        mode: "source",
        file: nil,
        source: @source,
        predicate: @predicate,
        engine: "auto",
        trusted: false,
        allow_imports: @allow_imports,
        flags_schema: nil,
        default_flags: {}
      )

    run_result =
      Bi::ReportRunner.new(
        report: report_spec,
        flags: parse_json_hash!(@flags_json),
        page: @page,
        per_page: @per_page
      ).run!

    @sql = run_result.sql
    @executed_sql = run_result.executed_sql
    @result = run_result.result

    render :new
  rescue StandardError => e
    @error = e
    render :new, status: :unprocessable_entity
  end

  private

  def default_source_for(predicate)
    <<~LOGICA
      @Engine("sqlite");

      #{predicate}(customer_name:, total_cents:) :-
        `((select
            c.name as customer_name,
            sum(o.amount_cents) as total_cents
          from customers c
          join orders o on o.customer_id = c.id
          group by c.name
          order by total_cents desc
          limit 20))`(customer_name:, total_cents:);
    LOGICA
  end

  def parse_json_hash!(text)
    obj = JSON.parse(text.to_s)
    raise ArgumentError, "flags must be a JSON object" unless obj.is_a?(Hash)

    obj
  end
end
