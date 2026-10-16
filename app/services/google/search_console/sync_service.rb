# encoding: UTF-8

module Google
  module SearchConsole
    # Recent days are fetched again because Google keeps revising them until
    # it calls them final. Days it has called final are skipped, since
    # fetching them again can't change anything.
    class SyncService
      SCOPE = "https://www.googleapis.com/auth/webmasters.readonly"
      QUERY_URL = "https://searchconsole.googleapis.com/webmasters/v3/sites/%{site}/searchAnalytics/query"
      SITE_URL = "https://searchconsole.googleapis.com/webmasters/v3/sites/%{site}"
      # An unverified user still sees the property listed but can read none
      # of its data.
      READABLE_PERMISSIONS = %w[siteOwner siteFullUser siteRestrictedUser].freeze
      DEFAULT_DAYS = 120
      # The API's maximum page size.
      ROW_LIMIT = 25_000
      # Page totals come from their own report: the per-query one leaves out
      # withheld queries, so its rows add up to less than the page's real total.
      # Discover and Google News aren't searched, so they have no queries, and
      # Search Console refuses to split Discover by device. It also refuses to
      # group search appearance with any other dimension, so appearances are
      # fetched one by one as a filter instead.
      BREAKDOWNS = [
        {model: Stat, dimension: nil},
        {model: Stat, dimension: "query", field: :query, skip: %w[discover googleNews]},
        {model: CountryStat, dimension: "country", field: :country},
        {model: DeviceStat, dimension: "device", field: :device, skip: %w[discover]},
        {model: AppearanceStat, dimension: "searchAppearance", field: :appearance, as_filter: true},
        {model: QueryCountryStat, dimension: %w[query country], field: %i[query country], skip: %w[discover googleNews], site_only: true},
        # Hours take the place of days, and only hourly data can be asked
        # for by hour.
        {model: HourStat, dimension: nil, hourly: true}
      ].freeze
      # Search Console keeps about this many days of hours.
      HOURLY_DAYS = HourStat::RETAINED_DAYS
      # Each once per page and once for the whole site, since Search Console
      # counts a result once per page shown in it but once for the site, and
      # its own totals and tabs (other than Pages) are the site's.
      REPORTS = BREAKDOWNS.flat_map { |report| report[:site_only] ? [report.merge(site: true)] : [report, report.merge(site: true)] }.freeze
      UNKNOWN_COUNTRY = "ZZ"
      # Google reports no incomplete day when the range has none, but also
      # when it has no rows for those days. These last few days are refetched
      # anyway, since Google usually revises that many.
      SETTLING_DAYS = 3

      class << self
        def call(...)
          new(...).call
        end

        # Counted from the last unsettled day rather than fixed, so a run
        # after a missed schedule still catches up on the days in between.
        def unsettled_days(today = Date.current)
          date = FinalDate.first_incomplete_date
          date ? (today - date).to_i + 1 : DEFAULT_DAYS
        end
      end

      # Must match Search Console's name for the property exactly
      # ("sc-domain:example.com", or the URL prefix with its trailing slash),
      # because the API looks the property up by it.
      def initialize(options = {})
        @site = options.fetch(:site) { Rails.application.credentials.dig(:google, :search_console_site) }
        @client = options.fetch(:client) { ApiClient.new(scope: SCOPE) }
        @end_date = options.fetch(:today) { Date.current }
        @start_date = @end_date - (options.fetch(:days, DEFAULT_DAYS).to_i.clamp(1..) - 1)
        @first_incomplete_dates = []
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        return result.tap { result.errors << "No Search Console site configured (credentials google.search_console_site)" } if @site.blank?

        access_error = site_access_error
        return result.tap { result.errors << access_error } if access_error

        synced = SyncLock.hold("google/search_console/performance") do
          Performance::SEARCH_TYPES.each do |search_type|
            REPORTS.each do |report|
              next if report[:skip]&.include?(search_type)

              report[:model].sync(rows(report, search_type), result, scope: existing_rows(report, search_type))
            # One refused report shouldn't cost the others.
            rescue ApiClient::Error => e
              result.errors << "Search Console: #{e.message}"
            end
          end
          record_first_incomplete_date(result)
        end
        result.errors << "Search Console: another sync is already running, so this one was skipped" unless synced
        # A setup problem fails every report alike; one line says it.
        result.errors.uniq!
        result
      end

      private

      # Checked first, so lost access reads as one line naming the fix rather
      # than every report refused alike.
      def site_access_error
        permission = @client.get(format(SITE_URL, site: ERB::Util.url_encode(@site)))["permissionLevel"]
        return if READABLE_PERMISSIONS.include?(permission)

        "Search Console: the service account is #{permission || "no user"} on #{@site}, which can read none of its data. " \
          "Add it under Settings › Users and permissions."
      rescue ApiClient::Error => e
        "Search Console: can't open #{@site} (#{e.message}). " \
          "Check the property name matches Search Console's exactly and that the service account is a user on it."
      end

      # Only a run that fetched every report, over a range that includes the
      # day already recorded, moves it: a refused report or a skipped gap
      # could leave an earlier day unsettled. Days are compared across all
      # reports and search types, since each settles on its own.
      def record_first_incomplete_date(result)
        return if result.errors.any?

        recorded = FinalDate.first_incomplete_date
        return if recorded && !(@start_date..@end_date).cover?(recorded)

        FinalDate.record(@first_incomplete_dates.min || @end_date - (SETTLING_DAYS - 1))
      end

      # Every search type, the site and each page, and pages with and without
      # queries share one collection, so a day's lookup is kept to the rows
      # this report could match rather than loading them all for each report.
      # Rows stored before search types existed have none, and read as web.
      def existing_rows(report, search_type)
        types = search_type == report[:model].fields["search_type"].default_val ? [search_type, nil] : [search_type]
        scope = report[:model].where(:search_type.in => types)
        scope = report[:site] ? scope.site_wide : scope.per_page
        return scope unless report[:model] == Stat

        report[:field] ? scope.by_query : scope.where(query: nil)
      end

      def rows(report, search_type)
        return filtered_rows(report, search_type) if report[:as_filter]

        dimensions = [*row_dimensions(report), *report[:dimension]]
        fields = Array(report[:field])
        fetch_all(dimensions, search_type, **hourly_options(report)).map do |row|
          breakdown = fields.zip(row["keys"].last(fields.size)).to_h { |field, value| [field, normalize(field, value)] }
          performance_row(row, search_type, report, breakdown)
        end
      end

      def row_dimensions(report)
        [report[:hourly] ? "hour" : "date", *("page" unless report[:site])]
      end

      # Listed first on their own, the one way Google allows, so each value's
      # pages and days can then be asked for with it as a filter.
      def filtered_rows(report, search_type)
        fetch_all([report[:dimension]], search_type).flat_map do |listed|
          value = listed["keys"].first
          filter = {dimensionFilterGroups: [{filters: [{dimension: report[:dimension], operator: "equals", expression: value}]}]}
          fetch_all(row_dimensions(report), search_type, filter).map do |row|
            performance_row(row, search_type, report, report[:field] => normalize(report[:field], value))
          end
        end
      end

      # Always everything Search Console keeps, however short the range, so a
      # short sync can't leave hours it still has unfetched.
      def hourly_options(report)
        return {} unless report[:hourly]

        {data_state: "hourly_all", start_date: @end_date - (HOURLY_DAYS - 1)}
      end

      # An hour's day is the Pacific one it's given in, as a day's figures are.
      def performance_row(row, search_type, report, breakdown)
        time = row["keys"].first
        page = row["keys"][1] unless report[:site]
        {
          date: Date.iso8601(time[0, 10]), **(report[:hourly] ? {hour_at: Time.iso8601(time).utc} : {}),
          search_type: search_type, page: page, page_path: (page_path(page) if page),
          clicks: row["clicks"].to_i, impressions: row["impressions"].to_i,
          ctr: row["ctr"].to_f, position: row["position"].to_f, **breakdown
        }
      end

      # Values are put in the form Analytics reports them, so the two sources
      # divide traffic by the same countries and devices.
      def normalize(field, value)
        case field
        when :country then CountryCodes.from_iso3(value) || UNKNOWN_COUNTRY
        when :device then value.to_s.downcase
        else value
        end
      end

      def page_path(page)
        URI.parse(page).path.presence || "/"
      rescue URI::InvalidURIError
        nil
      end

      # "all" includes the last couple of days, which "final" data leaves
      # out; they're corrected on later runs. Where they start is kept, so
      # later runs can skip the days before it.
      def fetch_all(dimensions, search_type, filter = {}, data_state: "all", start_date: @start_date)
        url = format(QUERY_URL, site: ERB::Util.url_encode(@site))
        rows = []
        loop do
          response = @client.post(url, {
            startDate: start_date.iso8601, endDate: @end_date.iso8601, dimensions: dimensions, type: search_type,
            dataState: data_state, rowLimit: ROW_LIMIT, startRow: rows.size, **filter
          })
          incomplete = response.dig("metadata", "first_incomplete_date")
          @first_incomplete_dates << Date.iso8601(incomplete) if incomplete
          page = response.fetch("rows", [])
          rows.concat(page)
          return rows if page.size < ROW_LIMIT
        end
      end
    end
  end
end
