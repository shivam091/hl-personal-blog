# encoding: UTF-8

module Google
  module SearchConsole
    class PerformanceController < ApplicationController
      include DailyReport

      # Google flags hourly data as possibly partial and keeps revising a day's
      # figures for a few days, so hours are only worth checking against Days
      # once the day has settled.
      HOURS_NOTE = "Search Console marks its hourly figures as possibly partial: the latest hours can still change, and a page's smaller " \
        "counts can be left out, so hours can add up to a little more or less than their day. " \
        "Compare them with Days once the day has settled, which takes Search Console a few days."

      BREAKDOWNS = {
        "pages" => DailyReport::Breakdown.new(key: "pages", label: "Pages", keys: [:page], headings: ["Page"], criteria: -> { Stat.page_totals }),
        "queries" => DailyReport::Breakdown.new(key: "queries", label: "Queries", keys: [:query], headings: ["Query"], criteria: -> { Stat.by_query }),
        "query-pages" => DailyReport::Breakdown.new(key: "query-pages", label: "Queries + pages", keys: [:query, :page], headings: ["Query", "Page"], criteria: -> { Stat.by_query },
          parent: "queries", split_label: "By page"),
        "countries" => DailyReport::Breakdown.new(key: "countries", label: "Countries", keys: [:country], headings: ["Country"], criteria: -> { CountryStat.all }),
        "devices" => DailyReport::Breakdown.new(key: "devices", label: "Devices", keys: [:device], headings: ["Device"], criteria: -> { DeviceStat.all }),
        "appearances" => DailyReport::Breakdown.new(key: "appearances", label: "Search appearance", keys: [:appearance], headings: ["Search appearance"], criteria: -> { AppearanceStat.all }),
        "days" => DailyReport::Breakdown.new(key: "days", label: "Days", keys: [:date], headings: ["Date"], criteria: -> { Stat.where(query: nil) }, default_sort: {"date" => "desc"}),
        "hours" => DailyReport::Breakdown.new(key: "hours", label: "Hours", keys: [:hour_at], headings: ["Hour (Pacific Time)"], criteria: -> { HourStat.all }, default_sort: {"hour_at" => "desc"}, caution: HOURS_NOTE)
      }.freeze
      # The param is the period comparison's own, so picking one of those from
      # its menu ends this; its menu reads as off meanwhile, since no period is
      # being compared.
      class TypeComparison < SimpleDelegator
        attr_reader :search_type

        def initialize(period, search_type)
          super(period)
          @search_type = search_type
        end

        def compare?
          true
        end

        def compare
          "off"
        end

        def query
          super.merge(vs: search_type)
        end

        def preset_query(preset)
          super.merge(vs: search_type)
        end

        def previous
          ComparedType.new(__getobj__, search_type)
        end
      end

      class ComparedType < SimpleDelegator
        attr_reader :search_type

        def initialize(period, search_type)
          super(period)
          @search_type = search_type
        end

        def to_s
          TABS.choices.fetch(search_type).first
        end
      end

      # Search Console reports each surface separately, so mixing them is a
      # choice rather than the only view.
      TABS = Filtering::Tabs.new(:type, field: :search_type, label: "Filter by search type (counts are clicks)",
        choices: {
          "web" => ["Web", "web"], "image" => ["Image", "image"], "video" => ["Video", "video"],
          "news" => ["News", "news"], "discover" => ["Discover", "discover"], "googleNews" => ["Google News", "googleNews"]
        })
      # Coloured away from green and red, which a change already uses for
      # better and worse, and stepped so every neighbouring pair stays apart
      # under colour blindness.
      METRICS = [
        DailyReport::Metric.new(field: :clicks, color: "#1d4ed8", label: "Clicks", tile_label: "Total clicks", format: :count, icon: "mouse-pointer", row_change: true,
          hint: "How often someone clicked a link from Google to your site."),
        DailyReport::Metric.new(field: :impressions, color: "#86198f", label: "Impressions", tile_label: "Total impressions", format: :count, icon: "eye", row_change: true,
          hint: "How often someone saw a link to your site on Google."),
        DailyReport::Metric.new(field: :ctr, color: "#0e8aa6", label: "CTR", tile_label: "Average CTR", format: :percent, icon: "trending-up", row_change: true,
          hint: "Click-through rate: the calculation of clicks ÷ impressions."),
        DailyReport::Metric.new(field: :position, color: "#a16207", label: "Average position", format: :position, icon: "bar-chart", lower_is_better: true, row_change: true,
          hint: "A relative ranking of the position of your link on Google, where 1 is the topmost position. Averaged over impressions, so lower is better.")
      ].freeze
      # Each is stored split by day and page only, never by another of them,
      # so a search by one reads that one's rows, and can't be crossed with
      # another, or with a breakdown other than pages, days or its own.
      DIMENSIONS = {
        query: -> { Stat.by_query }, country: -> { CountryStat.all }, device: -> { DeviceStat.all }, appearance: -> { AppearanceStat.all }
      }.freeze
      # Listed a row per page, so read from the per-page rows.
      PAGE_BREAKDOWNS = %w[pages query-pages].freeze
      BREAKDOWN_DIMENSIONS = {"queries" => :query, "query-pages" => :query, "countries" => :country, "devices" => :device, "appearances" => :appearance}.freeze
      DIMENSION_LABELS = {query: "queries", country: "countries", device: "devices", appearance: "search appearances"}.freeze
      TABLE_FOLLOWS_TREND = true
      EXPORT_NAME = "search-console"
      SYNC_SOURCE = "Search Console"
      SYNC_KIND = "search_console_performance"

      private

      # Search Console holds only 16 months, so earlier days can't be fetched.
      def sync_earliest
        Date.current - 16.months
      end

      def unsettled_from
        FinalDate.first_incomplete_date
      end

      def load_report
        super
        read_type_comparison
      end

      def load_page
        super
        load_inspections if PAGE_BREAKDOWNS.include?(@breakdown.key)
      end

      # Only for the rows shown, since each is held per page.
      def load_inspections
        pages = CrawledPage.where(:url.in => @rows.map { |row| row[:page] }).pluck(:url, :_id, :indexed).to_h { |url, id, indexed| [url, [id, indexed]] }
        verdicts = UrlInspection.where(:crawled_page_id.in => pages.values.map(&:first)).pluck(:crawled_page_id, :_id).to_h
        @inspections = pages.transform_values { |id, indexed| {page: id, inspection: verdicts[id], indexed: indexed} }
      end

      # Every search is offered on every breakdown, so a value picked on one
      # tab carries to the next.
      def shared_search_fields
        @shared_search_fields ||= [
          DailyReport::PATH_SEARCH,
          Filtering::Match.new(:query, field: :query, label: "Query", placeholder: "e.g. css grid"),
          Filtering::Select.new(:country, field: :country, label: "Country", choices: CountryStat.distinct(:country).compact.sort),
          Filtering::Select.new(:device, field: :device, label: "Device", choices: %w[desktop mobile tablet]),
          Filtering::Select.new(:appearance, field: :appearance, label: "Search appearance", choices: AppearanceStat.distinct(:appearance).compact.sort)
        ]
      end

      def searched_dimensions
        DIMENSIONS.keys.select { |dimension| @filtering.values[dimension] }
      end

      def unanswerable_search
        searched = searched_dimensions
        own = BREAKDOWN_DIMENSIONS[@breakdown.key]
        if hourly? && searched.any?
          "Search Console's hours aren't stored by #{DIMENSION_LABELS[searched.first]}. Remove the #{DIMENSION_LABELS[searched.first].singularize} search, or open Days."
        elsif searched.size > 1
          "Search Console's figures are stored split by one of #{searched.map { |dimension| DIMENSION_LABELS[dimension] }.to_sentence} at a time, so they can't be searched by both. Remove all but one."
        elsif searched.any? && own && searched != [own]
          "Search Console's figures aren't stored split by #{DIMENSION_LABELS[own]} and #{DIMENSION_LABELS[searched.first]} together. Open Pages or Days, or remove the #{DIMENSION_LABELS[searched.first].singularize} search."
        end
      end

      # A searched dimension's own rows, since that's the only place a query's
      # pages or a country's days are stored. Site-wide unless pages are asked
      # for, to match Search Console's own tabs.
      def breakdown_criteria
        criteria = searched_source || super
        criteria = criteria.where(:_id.in => []) if unanswerable_search
        PAGE_BREAKDOWNS.include?(@breakdown.key) || @filtering.values[:path] ? criteria.per_page : criteria.site_wide
      end

      def totals_criteria(period)
        filtered(period, totals_source)
      end

      # The compared type in place of the tab's, the searches kept, so both
      # sides are the same figures for a different surface.
      def filtered(period, criteria)
        scoped = period.apply(criteria)
        period.is_a?(ComparedType) ? TABS.apply(@filtering.searched(scoped), period.search_type) : @filtering.apply(scoped)
      end

      # Only once a type is picked and the other one has impressions here,
      # since a type with none would read as every figure new; Search Console
      # gives Discover and Google News no queries, and Discover no devices.
      def read_type_comparison
        @compared_type = params[:vs].presence_in(TABS.choices.keys)
        return unless @compared_type && @filtering.tab && @compared_type != @filtering.tab

        compared = TypeComparison.new(@period, @compared_type)
        if filtered(compared.previous, totals_source).where(:impressions.gt => 0).exists?
          @period = compared
        else
          @type_comparison_note = "#{compared.previous} has no impressions here over these dates, so there's nothing to compare it with."
        end
      end

      # Hours add up to their own totals, since they're counted apart from
      # the days and cover only the last few.
      def totals_source
        criteria = searched_source || (hourly? ? HourStat.all : Stat.where(query: nil))
        criteria = criteria.where(:_id.in => []) if unanswerable_search
        @filtering.values[:path] ? criteria.per_page : criteria.site_wide
      end

      # A day or an hour has no counterpart in the period before, so it has
      # no change to show; under another type it's the same day.
      def previous_rows
        super unless %w[days hours].include?(@breakdown.key) && !@period.is_a?(TypeComparison)
      end

      # The breakdown's own rows, since the totals are site-wide and hold no
      # page or query to match.
      def previous_rows_criteria(period)
        filtered(period, breakdown_criteria)
      end

      def hourly?
        @breakdown.key == "hours"
      end

      # Hours are kept by no dimension, so a search by one is left to
      # unanswerable_search to explain.
      def searched_source
        dimension = searched_dimensions.first
        return if dimension.nil? || hourly?

        DIMENSIONS[dimension]&.call
      end

      # An hour Google had nothing for is a gap rather than a zero, so it
      # doesn't read as a drop.
      def load_trend(selection)
        return super unless hourly?

        criteria = totals_criteria(@period)
        rows = criteria.klass.grouped(criteria, by: [:hour_at]).index_by { |row| row[:hour_at] }
        hours = rows.empty? ? [] : (0..((rows.keys.max - rows.keys.min) / 1.hour).round).map { |step| rows.keys.min + step.hours }
        DailyReport::Trend.new(
          dates: hours.map { |hour| hour.in_time_zone(HourStat::TIME_ZONE) },
          selection: selection,
          per: "hour",
          values: selection.available.index_with { |field| hours.map { |hour| rows[hour]&.value(field) } }
        )
      end

      # Clicks rather than row counts, since a count of grouped rows says
      # nothing about how much a surface matters.
      def tab_counts(_searched)
        searched = @filtering.searched(@period.apply(totals_source))
        clicks = searched.collection.aggregate([
          {"$match" => searched.selector},
          {"$group" => {"_id" => "$search_type", "clicks" => {"$sum" => "$clicks"}}}
        ]).to_h { |row| [row["_id"], row["clicks"]] }
        TABS.options.to_h { |_label, key| [key, key ? clicks.fetch(key, 0) : clicks.values.sum] }
      end
    end
  end
end
