# encoding: UTF-8

module Google
  module Analytics
    # The lists are picked here rather than in the view, so each one's CSV
    # export picks rows the same way, only without the limit.
    class Insights
      # Below this, a rate is mostly noise.
      MIN_VIEWS = 20
      MIN_SESSIONS = 20
      # Fewer pages than this, and one page swings a correlation either way.
      MIN_SPEED_PAGES = 5
      EXPORTS = {
        "changes" => "Page changes",
        "unengaging" => "Pages that don't hold readers",
        "read-through" => "Read-through",
        "landing-pages" => "Landing pages that lose readers",
        "sites" => "Referring sites",
        "channels" => "Channels",
        "times" => "When readers come"
      }.freeze
      # Stands in for reading to the end, since GA's enhanced measurement
      # fires it only once a reader nears a page's end.
      SCROLL_EVENT = "scroll"

      PageChange = Struct.new(:page_path, :views, :previous_views, keyword_init: true) do
        def change
          views - previous_views
        end

        # Nil for a page with no views before, so it reads as new rather
        # than as an endless rise.
        def growth
          change.fdiv(previous_views) if previous_views.positive?
        end
      end

      ReadThrough = Struct.new(:page_path, :views, :scrolls, keyword_init: true) do
        def rate
          scrolls.fdiv(views) if views.positive?
        end
      end

      SiteReferral = Struct.new(:host, :views, :previous_views, keyword_init: true) do
        def new?
          previous_views.zero?
        end
      end

      Channel = Struct.new(
        :channel_group, :views, :previous_views, :engagement_rate, :key_events,
        :new_users, keyword_init: true
      ) do
        def growth
          (views - previous_views).fdiv(previous_views) if previous_views&.positive?
        end
      end

      attr_reader :period, :country

      def initialize(period, country: nil)
        @period = period
        @country = country
      end

      def any?
        Stat.exists?
      end

      # A period from before the first sync would read as every page new.
      def previous?
        return @previous if defined?(@previous)

        @previous = period.compare_countries? || Stat.where(:date.lte => period.previous.from).exists?
      end

      # Scrolls, landing pages and sources aren't split by country, so they
      # can't be judged against another one.
      def previous_unsplit?
        previous? && !period.compare_countries?
      end

      def totals(within = period)
        @totals ||= {}
        @totals[within.key] ||= Stat.grouped(pages_criteria(within), by: []).totals
      end

      def previous_totals
        totals(period.previous) if previous?
      end

      # Every page with views in either period, so one that lost all of them
      # still shows as falling.
      def page_changes
        @page_changes ||= begin
          now = pages.transform_values(&:views)
          before = previous? ? pages(period.previous).transform_values(&:views) : {}
          (now.keys | before.keys).map do |path|
            PageChange.new(page_path: path, views: now.fetch(path, 0), previous_views: before.fetch(path, 0))
          end
        end
      end

      def rising_pages(limit: 10)
        return [] unless previous?

        page_changes.select do |row|
          row.change.positive?
        end.sort_by do |row|
          [-row.change, row.page_path]
        end.first(limit || page_changes.size)
      end

      def falling_pages(limit: 10)
        return [] unless previous?

        page_changes.select do |row|
          row.change.negative?
        end.sort_by do |row|
          [row.change, row.page_path]
        end.first(limit || page_changes.size)
      end

      # Read often but engaged with less than the site usually is: their
      # openings are the ones worth rewriting.
      def unengaging_pages(limit: 10)
        site_rate = totals.engagement_rate
        rows = pages.values.select { |row| row.views >= MIN_VIEWS && row.engagement_rate < site_rate }
        rows.sort_by { |row| [-row.views, row[:page_path].to_s] }.first(limit || rows.size)
      end

      # Scroll events carry no country, so this is always every country's.
      def read_through(limit: 10)
        rows = read_through_rows.select { |row| row.views >= MIN_VIEWS }
        rows.sort_by { |row| [row.rate, -row.views, row.page_path] }.first(limit || rows.size)
      end

      def site_read_through(within = period)
        rows = read_through_rows(within)
        views = rows.sum(&:views)
        rows.sum(&:scrolls).fdiv(views) if views.positive?
      end

      def scrolls?
        read_through_rows.any? { |row| row.scrolls.positive? }
      end

      # Landing pages have no country breakdown, so these are every country's.
      def landing_totals(within = period)
        @landing_totals ||= {}
        @landing_totals[within.key] ||= LandingPageStat.grouped(within.apply(LandingPageStat.all), by: []).totals
      end

      # Where readers arrive but don't stay: the first page they see is the
      # one to fix.
      def leaking_landing_pages(limit: 10)
        site_rate = landing_totals.engagement_rate
        rows = LandingPageStat.grouped(period.apply(LandingPageStat.all), by: [:page_path])
                 .select { |row| row.sessions >= MIN_SESSIONS && row.engagement_rate < site_rate }
        rows.sort_by { |row| [-row.sessions, row[:page_path].to_s] }.first(limit || rows.size)
      end

      # By site rather than by page linked from, so one site's links read as
      # one source; the blog's own pages and direct visits aren't a site
      # sending readers.
      def referring_sites
        @referring_sites ||= begin
          now = referrer_hosts(period)
          before = previous_unsplit? ? referrer_hosts(period.previous) : {}
          now.map do |host, views|
            SiteReferral.new(host: host, views: views, previous_views: before.fetch(host, 0))
          end.sort_by { |row| [-row.views, row.host] }
        end
      end

      def new_referring_sites(limit: 10)
        return [] unless previous_unsplit?

        rows = referring_sites.select(&:new?)
        rows.first(limit || rows.size)
      end

      # Views say how many readers a channel sends; engagement and key events
      # say whether they're worth having. New users are credited to the
      # channel that first brought each reader, as GA's User acquisition
      # does, since a later visit's channel didn't win them.
      def channels
        @channels ||= begin
          before = previous_unsplit? ? channel_rows(period.previous).to_h { |row| [row[:channel_group], row.views] } : {}
          new_users = UserAcquisitionStat.grouped(period.apply(UserAcquisitionStat.all), by: [:first_channel_group])
                        .to_h { |row| [row[:first_channel_group], row.new_users] }
          channel_rows(period).map do |row|
            Channel.new(
              channel_group: row[:channel_group],
              views: row.views,
              previous_views: before[row[:channel_group]],
              engagement_rate: row.engagement_rate,
              key_events: row.key_events,
              new_users: new_users.fetch(row[:channel_group], 0)
            )
          end.sort_by { |row| [-row.views, row.channel_group.to_s] }
        end
      end

      # Every weekday and hour, quiet ones too, so the busiest stand out
      # against the rest. Not split by country, so always every country's.
      def views_by_day
        @views_by_day ||= time_views(:day_of_week, (0..6).map(&:to_s))
      end

      def views_by_hour
        @views_by_hour ||= time_views(:hour, (0..23).map { |hour| format("%02d", hour) })
      end

      def reading_times?
        views_by_hour.values.any?(&:positive?)
      end

      def to_csv(export)
        CSV.generate do |csv|
          case export
          when "changes"
            csv << ["Page", "Views", "Views before", "Change"]
            page_changes.sort_by { |row| [-row.change.abs, row.page_path] }.each do |row|
              csv << [
                row.page_path,
                row.views,
                (row.previous_views if previous?),
                (row.change if previous?)
              ]
            end
          when "unengaging"
            csv << ["Page", "Views", "Engagement rate", "Engagement per user (s)"]
            unengaging_pages(limit: nil).each do |row|
              csv << [
                row[:page_path],
                row.views,
                row.engagement_rate.round(4),
                row.average_engagement_seconds.round(1)
              ]
            end
          when "read-through"
            csv << ["Page", "Views", "Scrolls", "Read-through rate"]
            read_through(limit: nil).each do |row|
              csv << [row.page_path, row.views, row.scrolls, row.rate.round(4)]
            end
          when "landing-pages"
            csv << ["Landing page", "Sessions", "Engagement rate", "Engagement per session (s)"]
            leaking_landing_pages(limit: nil).each do |row|
              csv << [
                row[:page_path],
                row.sessions,
                row.engagement_rate.round(4),
                row.average_engagement_seconds_per_session.round(1)
              ]
            end
          when "sites"
            csv << ["Site", "Views", "Views before", "New"]
            referring_sites.each do |row|
              csv << [
                row.host,
                row.views,
                (row.previous_views if previous?),
                ((row.new? ? "Yes" : "No") if previous?)
              ]
            end
          when "channels"
            csv << ["Channel", "Views", "Views before", "New users", "Engagement rate", "Key events"]
            channels.each do |row|
              csv << [
                row.channel_group,
                row.views,
                row.previous_views,
                row.new_users,
                row.engagement_rate.round(4),
                row.key_events
              ]
            end
          when "times"
            csv << ["Day", "Hour", "Views"]
            views_by_day.each { |day, views| csv << [Google::DailyReport.value_label(:day_of_week, day), nil, views] }
            views_by_hour.each { |hour, views| csv << [nil, Google::DailyReport.value_label(:hour, hour), views] }
          end
        end
      end

      SpeedPoint = Struct.new(:page_path, :views, :lcp_ms, :performance, :engagement_rate, keyword_init: true)

      # Phones' lab LCP, since most readers come on one and a lab run is
      # measured the same way for every page, unlike real readers' figures
      # that only well-read pages have.
      def speed_points(strategy: "mobile")
        results = Google::PageSpeed::Result.where(strategy: strategy, :lab_lcp_ms.ne => nil)
          .only(:page_path, :lab_lcp_ms, :performance).index_by(&:page_path)
        pages.values.filter_map do |row|
          result = results[row[:page_path]]
          next unless result && row.views >= MIN_VIEWS

          SpeedPoint.new(page_path: row[:page_path], views: row.views, lcp_ms: result.lab_lcp_ms, performance: result.performance,
            engagement_rate: row.engagement_rate)
        end
      end

      # Pearson's r between load time and engagement: below zero, slower pages
      # hold readers less. Withheld on so few pages a single one swings it.
      def speed_correlation(points = speed_points)
        return if points.size < MIN_SPEED_PAGES

        xs = points.map(&:lcp_ms)
        ys = points.map(&:engagement_rate)
        mean_x = xs.sum / xs.size
        mean_y = ys.sum / ys.size
        covariance = xs.zip(ys).sum { |x, y| (x - mean_x) * (y - mean_y) }
        spread = Math.sqrt(xs.sum { |x| (x - mean_x)**2 } * ys.sum { |y| (y - mean_y)**2 })
        covariance / spread if spread.positive?
      end

      OutboundLink = Struct.new(:url, :clicks, :pages, :check, keyword_init: true)
      OutboundPage = Struct.new(:page_path, :clicks, :views, keyword_init: true) do
        # Clicks out per view, so a short page with a few links isn't
        # outranked by a long-read one on volume alone.
        def rate
          clicks.fdiv(views) if views.positive?
        end
      end

      # With Safe Browsing's verdict, since a link readers follow most is
      # the one that does most harm once its site turns bad.
      def outbound_links(limit: 10)
        rows = outbound_rows.group_by { |row| row[:link_url] }
        checks = Google::SafeBrowsing::LinkCheck.where(:url.in => rows.keys).index_by(&:url)
        rows.map do |url, pages|
          OutboundLink.new(url: url, clicks: pages.sum(&:event_count), pages: pages.size, check: checks[url])
        end.sort_by { |row| [-row.clicks, row.url] }.first(limit)
      end

      def outbound_sites
        outbound_rows.each_with_object(Hash.new(0)) { |row, hosts| hosts[referrer_host(row[:link_url]) || row[:link_url]] += row.event_count }
      end

      # Views from every country, as outbound clicks aren't split by one,
      # so the rate divides like by like.
      def outbound_pages(limit: 10)
        views = Stat.grouped(period.apply(Stat.all), by: [:page_path]).to_h { |row| [row[:page_path], row.views] }
        outbound_rows.group_by { |row| row[:page_path] }.map do |path, links|
          OutboundPage.new(page_path: path, clicks: links.sum(&:event_count), views: views.fetch(path, 0))
        end.sort_by { |row| [-row.clicks, row.page_path] }.first(limit)
      end

      private

      def outbound_rows
        @outbound_rows ||= OutboundLinkStat.grouped(period.apply(OutboundLinkStat.all), by: [:link_url, :page_path]).to_a
      end

      def pages(within = period)
        @pages ||= {}
        @pages[within.key] ||= Stat.grouped(pages_criteria(within), by: [:page_path]).index_by do |row|
          row[:page_path]
        end
      end

      # A country's pages come from the country breakdown, which carries the
      # same counts per page.
      def pages_criteria(within)
        code = within.country || country
        within.apply(code ? CountryStat.where(country: code) : Stat.all)
      end

      def scroll_counts(within = period)
        EventStat.grouped(within.apply(EventStat.where(event_name: SCROLL_EVENT)), by: [:page_path])
          .to_h { |row| [row[:page_path], row.event_count] }
      end

      def read_through_rows(within = period)
        @read_through_rows ||= {}
        @read_through_rows[within.key] ||= begin
          scrolls = scroll_counts(within)
          Stat.grouped(within.apply(Stat.all), by: [:page_path]).map do |row|
            ReadThrough.new(page_path: row[:page_path], views: row.views, scrolls: scrolls.fetch(row[:page_path], 0))
          end
        end
      end

      def time_views(key, slots)
        views = TimeOfDayStat.grouped(period.apply(TimeOfDayStat.all), by: [key]).to_h { |row| [row[key], row.views] }
        slots.index_with { |slot| views.fetch(slot, 0) }
      end

      def channel_rows(within)
        SourceStat.grouped(within.apply(SourceStat.all), by: [:channel_group]).to_a
      end

      def referrer_hosts(within)
        ReferrerStat.grouped(within.apply(ReferrerStat.all), by: [:referrer]).each_with_object(Hash.new(0)) do |row, hosts|
          host = referrer_host(row[:referrer])
          hosts[host] += row.views if host
        end
      end

      def referrer_host(referrer)
        host = URI.parse(referrer.to_s).host&.downcase&.delete_prefix("www.")
        host unless host.nil? || host == SyncService::HOSTNAME
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
