# encoding: UTF-8

module Google
  module SearchConsole
    # Impressions in AI Overviews and AI Mode, kept from uploaded exports of
    # Search Console's Generative AI report, since Google offers it through
    # no API.
    class GenerativeAiController < ApplicationController
      BREAKDOWNS = {
        "pages" => ["Pages", "Page"],
        "countries" => ["Countries", "Country"],
        "devices" => ["Devices", "Device"],
        "dates" => ["Dates", "Date"]
      }.freeze
      SORT_COLUMNS = {"impressions" => "desc", "label" => "asc"}.freeze
      COUNTRY_SORT_COLUMNS = {"impressions" => "desc", "country" => "asc"}.freeze
      DATE_SORT_COLUMNS = {"date" => "desc", "impressions" => "desc"}.freeze

      TOP_PAGES = 10
      # Those Search Console's own reports split the same way.
      SEARCH_BREAKDOWNS = %w[pages countries].freeze

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

        rows = dates? ? date_rows(stats) : breakdown_rows
        @pagination = Pagination.new(rows, params)
        @rows = @pagination.records.to_a
        @country_impressions = country_impressions if @breakdown == "countries"
        # Every search type's site-wide impressions, as Search Insights reads
        # its share, so the two agree. Not the upload's own type, which is
        # Google's label for it ("Web (text-based)") rather than the API's.
        @organic_daily = (@period.from..@period.to).zip(Summary.new(@period).daily(:impressions)).to_h
        @top_pages = top_pages if @breakdown == "pages"
        @search_impressions = search_impressions if @covered && SEARCH_BREAKDOWNS.include?(@breakdown)
      end

      def create
        file = params[:file]
        unless file.respond_to?(:path)
          return redirect_to google_search_console_generative_ai_path, alert: "Choose the spreadsheet Search Console's Export button made, then upload it."
        end

        workbook = GenerativeAiWorkbook.new(file.path)
        gaps = upload_gaps(workbook)
        result = GenerativeAiStat.record(workbook)
        GenerativeAiRow.replace(workbook)
        redirect_to google_search_console_generative_ai_path(SearchType.new(workbook.search_type, GenerativeAiStat.search_types.first).query),
          notice: "Uploaded #{workbook.search_type} impressions for #{l(workbook.from)} – #{l(workbook.to)}: " \
            "#{helpers.pluralize(result.created, "new day")}, #{helpers.pluralize(result.updated, "day")} updated." \
            "#{" No upload covers #{gaps.map { |gap| "#{l(gap.begin)} – #{l(gap.end)}" }.to_sentence}, so the chart has a gap there; export those days to fill it." if gaps.any?}"
      rescue GenerativeAiWorkbook::Error => error
        redirect_to google_search_console_generative_ai_path, alert: error.message
      end

      private

      def dates?
        @breakdown == "dates"
      end

      # The days between this upload and those kept either side of it, read
      # before it goes in, since a gap there is drawn as no figures at all.
      def upload_gaps(workbook)
        stats = GenerativeAiStat.where(search_type: workbook.search_type)
        before = stats.where(:date.lt => workbook.from).max(:date)&.to_date
        after = stats.where(:date.gt => workbook.to).min(:date)&.to_date
        [(before + 1..workbook.from - 1 if before && before < workbook.from - 1),
          (workbook.to + 1..after - 1 if after && after > workbook.to + 1)].compact
      end

      # Search Console's own impressions over the upload's range, by the same
      # key the table's rows are read by, so a row's AI share is of the days
      # its AI impressions were counted over.
      def search_impressions
        search = Summary.new(Period.new({from: @covered.begin.iso8601, to: @covered.end.iso8601}))
        rows = @breakdown == "pages" ? search.pages : search.countries
        rows.transform_values(&:impressions).select { |_, impressions| impressions.positive? }.presence
      end

      def date_rows(stats)
        @sorting = Sorting.new(params, columns: DATE_SORT_COLUMNS, tiebreaker: :date)
        @row_total = @total.value(:impressions)
        @sorting.apply(@period.apply(stats))
      end

      # Every country rather than a page of them, and summed by code, since
      # two of Google's names can share one. Those that matched no code stay
      # in the table only.
      def country_impressions
        @breakdowns.where(breakdown: "countries", :country.ne => nil).group_by(&:country).transform_values { |rows| rows.sum(&:impressions) }
      end

      # The busiest of every page, not of the table's page, so the chart
      # reads the same whichever page of the table is open.
      def top_pages
        @breakdowns.where(breakdown: "pages").order(impressions: :desc).limit(TOP_PAGES).to_a
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
