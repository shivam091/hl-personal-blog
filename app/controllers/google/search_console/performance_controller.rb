# encoding: UTF-8

module Google
  module SearchConsole
    # So search performance can be read without opening Search Console, and
    # for longer than the 16 months it keeps.
    class PerformanceController < ApplicationController
      include DailyReport

      BREAKDOWNS = {
        "pages" => DailyReport::Breakdown.new(key: "pages", label: "Pages", keys: [:page], headings: ["Page"], criteria: -> { Stat.page_totals }),
        "queries" => DailyReport::Breakdown.new(key: "queries", label: "Queries", keys: [:query], headings: ["Query"], criteria: -> { Stat.by_query }),
        # Which page answers which query, something Search Console's own
        # tabs only show one filter at a time; it's where two posts
        # competing for one query shows.
        "query-pages" => DailyReport::Breakdown.new(key: "query-pages", label: "Queries + pages", keys: [:query, :page], headings: ["Query", "Page"], criteria: -> { Stat.by_query },
          parent: "queries", split_label: "By page"),
        # What one market or device searches, which Search Console's own
        # tabs only show one filter at a time.
        "query-countries" => DailyReport::Breakdown.new(key: "query-countries", label: "Queries + countries", keys: [:query, :country], headings: ["Query", "Country"], criteria: -> { QueryCountryStat.all },
          parent: "queries", split_label: "By country"),
        "query-devices" => DailyReport::Breakdown.new(key: "query-devices", label: "Queries + devices", keys: [:query, :device], headings: ["Query", "Device"], criteria: -> { QueryDeviceStat.all },
          parent: "queries", split_label: "By device"),
        "country-devices" => DailyReport::Breakdown.new(key: "country-devices", label: "Countries + devices", keys: [:country, :device], headings: ["Country", "Device"], criteria: -> { CountryDeviceStat.all },
          parent: "countries", split_label: "By device"),
        "query-country-devices" => DailyReport::Breakdown.new(key: "query-country-devices", label: "Queries + countries + devices", keys: [:query, :country, :device],
          headings: ["Query", "Country", "Device"], criteria: -> { QueryCountryDeviceStat.all }, parent: "queries", split_label: "By country and device"),
        "countries" => DailyReport::Breakdown.new(key: "countries", label: "Countries", keys: [:country], headings: ["Country"], criteria: -> { CountryStat.all }),
        "devices" => DailyReport::Breakdown.new(key: "devices", label: "Devices", keys: [:device], headings: ["Device"], criteria: -> { DeviceStat.all }),
        "appearances" => DailyReport::Breakdown.new(key: "appearances", label: "Search appearance", keys: [:appearance], headings: ["Search appearance"], criteria: -> { AppearanceStat.all }),
        # Newest first, since recent days are what's usually being checked.
        "days" => DailyReport::Breakdown.new(key: "days", label: "Days", keys: [:date], headings: ["Date"], criteria: -> { Stat.where(query: nil) }, default_sort: {"date" => "desc"}),
        # The last ten days or so, hour by hour, to see how a post does
        # right after it's published or updated. Copying them began on 11
        # October 2026, and by query, country or device on 26 October, so
        # nothing earlier was kept.
        "hours" => DailyReport::Breakdown.new(key: "hours", label: "Hours", keys: [:hour_at], headings: ["Hour (Pacific Time)"], criteria: -> { HourStat.all }, default_sort: {"hour_at" => "desc"},
          note: "Hours are available from 11 October 2026 onward, and by query, country or device from 26 October 2026.")
      }.freeze
      # Search Console reports each surface separately, so mixing them is a
      # choice rather than the only view.
      TABS = Filtering::Tabs.new(:type, field: :search_type, label: "Filter by search type (counts are clicks)",
        choices: {
          "web" => ["Web", "web"], "image" => ["Image", "image"], "video" => ["Video", "video"],
          "news" => ["News", "news"], "discover" => ["Discover", "discover"], "googleNews" => ["Google News", "googleNews"]
        })
      # Worded as Search Console's own help defines them, so a figure means
      # the same here as there. Coloured in Search Console's hues, stepped so
      # every pair stays apart under colour blindness and each reads as text.
      # Each row's change shows once a comparison is picked, as Search
      # Console's compare columns do.
      METRICS = [
        DailyReport::Metric.new(field: :clicks, color: "#1f6fd1", label: "Clicks", tile_label: "Total clicks", format: :count, icon: "mouse-pointer", row_change: true,
          hint: "How often someone clicked a link from Google to your site."),
        DailyReport::Metric.new(field: :impressions, color: "#a3328a", label: "Impressions", tile_label: "Total impressions", format: :count, icon: "eye", row_change: true,
          hint: "How often someone saw a link to your site on Google."),
        DailyReport::Metric.new(field: :ctr, color: "#0b7d60", label: "CTR", tile_label: "Average CTR", format: :percent, icon: "trending-up", row_change: true,
          hint: "Click-through rate: the calculation of clicks ÷ impressions."),
        DailyReport::Metric.new(field: :position, color: "#b45c00", label: "Average position", format: :position, icon: "bar-chart", lower_is_better: true, row_change: true,
          hint: "A relative ranking of the position of your link on Google, where 1 is the topmost position. Averaged over impressions, so lower is better.")
      ].freeze
      # Each is stored split by day and page only, never by another of them
      # outside the crossed breakdowns, so a search by one reads that one's
      # rows, and can't be crossed with another, or with a breakdown other
      # than pages, days or its own.
      DIMENSIONS = {
        query: -> { Stat.by_query }, country: -> { CountryStat.all }, device: -> { DeviceStat.all }, appearance: -> { AppearanceStat.all }
      }.freeze
      # Listed a row per page, so read from the per-page rows.
      PAGE_BREAKDOWNS = %w[pages query-pages].freeze
      BREAKDOWN_DIMENSIONS = {"queries" => :query, "query-pages" => :query, "countries" => :country, "devices" => :device, "appearances" => :appearance}.freeze
      # Hours are stored by these site-wide as well, so the hours tab can be
      # searched by one of them, though not by page at the same time.
      HOURLY_DIMENSIONS = {query: -> { HourQueryStat.all }, country: -> { HourCountryStat.all }, device: -> { HourDeviceStat.all }}.freeze
      DIMENSION_LABELS = {query: "queries", country: "countries", device: "devices", appearance: "search appearances"}.freeze
      # Stored by these dimensions together, so a search by any of them reads
      # their own rows; site-wide only, so they can't be searched by page.
      CROSSED_BREAKDOWNS = {
        "query-countries" => %i[query country], "query-devices" => %i[query device],
        "country-devices" => %i[country device], "query-country-devices" => %i[query country device]
      }.freeze
      # Search Console's table shows only the figures ticked on its chart.
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

      def load_page
        super
        load_inspections if PAGE_BREAKDOWNS.include?(@breakdown.key)
      end

      # Only for the rows shown, so Inspect opens the verdict already held on
      # a page wherever there is one, and only a page Google hasn't indexed
      # offers an indexing request.
      def load_inspections
        pages = CrawledPage.where(:url.in => @rows.map { |row| row[:page] }).pluck(:url, :_id, :indexed).to_h { |url, id, indexed| [url, [id, indexed]] }
        verdicts = UrlInspection.where(:crawled_page_id.in => pages.values.map(&:first)).pluck(:crawled_page_id, :_id).to_h
        @inspections = pages.transform_values { |id, indexed| {page: id, inspection: verdicts[id], indexed: indexed} }
      end

      # Every search is offered on every breakdown, as Search Console's
      # filters are, so a value picked on one tab carries to the next.
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
        if crossed
          other = searched - crossed
          if @filtering.values[:path]
            "Search Console's #{crossed.map { |dimension| DIMENSION_LABELS[dimension] }.to_sentence(last_word_connector: " and ")} together are stored for the whole site only, not by page. Remove the page search, or open Queries + pages."
          elsif other.any?
            "Search Console's figures aren't stored split by #{[*crossed, other.first].map { |dimension| DIMENSION_LABELS[dimension] }.to_sentence(last_word_connector: " and ")} together. Remove the #{DIMENSION_LABELS[other.first].singularize} search."
          end
        elsif hourly? && (unhourly = searched - HOURLY_DIMENSIONS.keys).any?
          "Search Console's hours aren't stored by #{DIMENSION_LABELS[unhourly.first]}. Remove the #{DIMENSION_LABELS[unhourly.first].singularize} search, or open Days."
        elsif hourly? && searched.any? && @filtering.values[:path]
          "Search Console's hours by #{DIMENSION_LABELS[searched.first]} are stored for the whole site only, not by page. Remove the page search, or the #{DIMENSION_LABELS[searched.first].singularize} search."
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

      # Site-wide unless pages are searched, so the totals match Search
      # Console's own.
      def totals_criteria(period)
        @filtering.apply(period.apply(totals_source))
      end

      # Hours add up to their own totals, since they're counted apart from
      # the days and cover only the last few.
      def totals_source
        criteria = if crossed && searched_dimensions.any?
          @breakdown.criteria.call
        else
          searched_source || (hourly? ? HourStat.all : Stat.where(query: nil))
        end
        criteria = criteria.where(:_id.in => []) if unanswerable_search
        @filtering.values[:path] ? criteria.per_page : criteria.site_wide
      end

      # A day or an hour has no counterpart in the period before, so it has
      # no change to show.
      def previous_rows
        super unless %w[days hours].include?(@breakdown.key)
      end

      # The breakdown's own rows, since the totals are site-wide and hold no
      # page or query to match.
      def previous_rows_criteria(period)
        @filtering.apply(period.apply(breakdown_criteria))
      end

      def hourly?
        @breakdown.key == "hours"
      end

      # Hours are kept by fewer dimensions than days, so one they lack is
      # left to unanswerable_search to explain.
      def searched_source
        dimension = searched_dimensions.first
        return if dimension.nil? || crossed

        sources = hourly? ? HOURLY_DIMENSIONS : DIMENSIONS
        sources[dimension]&.call
      end

      def crossed
        CROSSED_BREAKDOWNS[@breakdown.key]
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
