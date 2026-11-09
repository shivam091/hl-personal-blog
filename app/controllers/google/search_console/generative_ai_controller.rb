# encoding: UTF-8

module Google
  module SearchConsole
    # Impressions in AI Overviews and AI Mode, kept from uploaded exports of
    # Search Console's Generative AI report, since Google offers it through
    # no API. Laid out as Search performance is, a tab per breakdown. Days
    # follow the period picked; pages, countries and devices are the latest
    # upload's, as Google totals them over its whole range.
    class GenerativeAiController < ApplicationController
      # Tab labels, with each one's column heading, in Search Console's order.
      BREAKDOWNS = {
        "pages" => ["Pages", "Page"],
        "countries" => ["Countries", "Country"],
        "devices" => ["Devices", "Device"],
        "dates" => ["Dates", "Date"]
      }.freeze
      # Busiest first, as Search Console lists them; days newest first.
      SORT_COLUMNS = {"impressions" => "desc", "label" => "asc"}.freeze
      # Countries are shown, so sorted, by code, as on Search performance.
      COUNTRY_SORT_COLUMNS = {"impressions" => "desc", "country" => "asc"}.freeze
      DATE_SORT_COLUMNS = {"date" => "desc", "impressions" => "desc"}.freeze

      # The search type rides along in tab, period, sort and page links, as a
      # list's filters do.
      SearchType = Struct.new(:value, :default) do
        def query
          value == default ? {} : {type: value}
        end
      end

      def index
        types = GenerativeAiStat.search_types
        @search_types = types
        @search_type = SearchType.new(params[:type].presence_in(types) || types.first, types.first)
        @breakdown = params[:breakdown].presence_in(BREAKDOWNS.keys) || BREAKDOWNS.keys.first
        @period = Period.new(params)
        stats = GenerativeAiStat.where(search_type: @search_type.value)

        @daily = @period.apply(stats).pluck(:date, :impressions).to_h
        @total = GroupedScope::Row.new("impressions" => (@daily.values.sum if @daily.any?))
        # Only with days kept from before the period compared with, since a
        # period before the first upload would read as a jump from nothing.
        if @period.compare? && stats.where(:date.lte => @period.previous.from).exists?
          @previous_daily = @period.previous.apply(stats).pluck(:date, :impressions).to_h
          @previous_total = GroupedScope::Row.new("impressions" => (@previous_daily.values.sum if @previous_daily.any?))
        end
        @breakdowns = GenerativeAiRow.where(search_type: @search_type.value)
        @covered = @breakdowns.first&.then { |row| row.from..row.to }
        # As dates, since MongoDB gives the least and greatest of them back as
        # midnight UTC times, which would print with a time and zone.
        @first_day, @last_day = [stats.min(:date), stats.max(:date)].map { |day| day&.to_date }

        rows = dates? ? date_rows(stats) : breakdown_rows
        @pagination = Pagination.new(rows, params)
        @rows = @pagination.records.to_a
      end

      def create
        file = params[:file]
        unless file.respond_to?(:path)
          return redirect_to google_search_console_generative_ai_path, alert: "Choose the spreadsheet Search Console's Export button made, then upload it."
        end

        workbook = GenerativeAiWorkbook.new(file.path)
        result = GenerativeAiStat.record(workbook)
        GenerativeAiRow.replace(workbook)
        redirect_to google_search_console_generative_ai_path(SearchType.new(workbook.search_type, GenerativeAiStat.search_types.first).query),
          notice: "Uploaded #{workbook.search_type} impressions for #{l(workbook.from)} – #{l(workbook.to)}: " \
            "#{helpers.pluralize(result.created, "new day")}, #{helpers.pluralize(result.updated, "day")} updated."
      rescue GenerativeAiWorkbook::Error => error
        redirect_to google_search_console_generative_ai_path, alert: error.message
      end

      private

      def dates?
        @breakdown == "dates"
      end

      # The period's days, each against the day at the same place in the
      # period compared with, as the chart reads them.
      def date_rows(stats)
        @sorting = Sorting.new(params, columns: DATE_SORT_COLUMNS, tiebreaker: :date)
        @row_total = @total.value(:impressions)
        @sorting.apply(@period.apply(stats))
      end

      # The latest upload's, whatever period is picked, since Google gives
      # them no days.
      def breakdown_rows
        @sorting = Sorting.new(params, columns: (@breakdown == "countries" ? COUNTRY_SORT_COLUMNS : SORT_COLUMNS), tiebreaker: :label)
        rows = @breakdowns.where(breakdown: @breakdown)
        @row_total = rows.sum(:impressions) if @covered
        @sorting.apply(rows)
      end
    end
  end
end
