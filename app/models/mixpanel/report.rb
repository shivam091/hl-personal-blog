# encoding: UTF-8

module Mixpanel
  # Added up in Ruby rather than aggregated in Mongo: a period is at most a
  # few thousand small rows, and the figures need sets of rows the database
  # would have to be asked for one by one.
  class Report
    Page = Struct.new(:page_path, :content_group, :page_views, :visitors, :engaged_views, :engaged_seconds, :scroll_percent_sum,
      :read_through_views, :rage_clicks, :dead_clicks, :js_errors, keyword_init: true) do
      def mean_engaged_seconds
        engaged_seconds.fdiv(engaged_views) if engaged_views.positive?
      end

      def mean_scroll_share
        scroll_percent_sum.fdiv(engaged_views * 100) if engaged_views.positive?
      end

      def read_through_share
        read_through_views.fdiv(engaged_views) if engaged_views.positive?
      end

      def frustrations
        rage_clicks + dead_clicks + js_errors
      end
    end

    Issue = Struct.new(:kind, :page_path, :target, :count, :visitors, keyword_init: true)

    SUMMED = %i[page_views visitors engaged_views engaged_seconds scroll_percent_sum read_through_views rage_clicks dead_clicks js_errors].freeze

    attr_reader :period

    def initialize(period)
      @period = period
    end

    def any?
      SiteStat.exists?
    end

    # Nil without a comparison, or before anything was synced for it, so the
    # first synced period isn't set against nothing as if it were a collapse.
    def previous
      return @previous if defined?(@previous)

      @previous = (Report.new(period.previous) if period.compare? && SiteStat.where(:date.lte => period.previous.to).exists?)
    end

    def days
      @days ||= period.apply(SiteStat.all).order(date: :asc).to_a
    end

    # Summed day by day, so a reader on two days counts twice, as GA's daily
    # user figures add up.
    def visitors
      days.sum(&:visitors)
    end

    def page_views
      days.sum(&:page_views)
    end

    def replays
      days.sum(&:replays)
    end

    def site
      @site ||= Page.new(page_path: "(all)", **SUMMED.index_with { |field| pages.sum(&field) })
    end

    def pages
      @pages ||= period.apply(PageStat.all).to_a.group_by(&:page_path).map do |path, rows|
        Page.new(page_path: path, content_group: rows.filter_map(&:content_group).last, **SUMMED.index_with { |field| rows.sum(&field) })
      end
    end

    def page(path)
      @pages_by_path ||= pages.index_by(&:page_path)
      @pages_by_path[path]
    end

    def top_pages(limit: 25)
      rows = pages.select { |page| page.page_views.positive? }.sort_by { |page| [-page.page_views, page.page_path] }
      limit ? rows.first(limit) : rows
    end

    # Pages readers leave early, among those read often enough to judge.
    def least_read_pages(min_views: 10, limit: 10)
      pages.select { |page| page.engaged_views >= min_views }.sort_by { |page| [page.read_through_share, page.page_path] }.first(limit)
    end

    def issues(kind, limit: 15)
      rows = period.apply(IssueStat.where(kind: kind)).to_a.group_by { |row| [row.page_path, row.target] }.map do |(path, target), group|
        Issue.new(kind: kind, page_path: path, target: target, count: group.sum(&:count), visitors: group.sum(&:visitors))
      end
      rows.sort_by { |issue| [-issue.count, issue.page_path, issue.target] }.first(limit)
    end

    # Each status's share of the readers Mixpanel saw: the blocked share is
    # the part of the audience absent from every GA report.
    def ga_shares
      shares_of(:ga_statuses)
    end

    def theme_shares
      shares_of(:themes)
    end

    def events
      counts = Hash.new(0)
      days.each { |day| day.events.each { |row| counts[row["name"]] += row["count"].to_i } }
      counts.sort_by { |name, count| [-count, name] }
    end

    def to_csv
      CSV.generate do |csv|
        csv << ["Page path", "Content group", "Page views", "Visitors", "Engaged views", "Mean engaged seconds", "Mean scroll depth",
          "Read-through share", "Rage clicks", "Dead clicks", "Script errors"]
        top_pages(limit: nil).each do |page|
          csv << [page.page_path, page.content_group, page.page_views, page.visitors, page.engaged_views, page.mean_engaged_seconds&.round(1),
            page.mean_scroll_share&.round(4), page.read_through_share&.round(4), page.rage_clicks, page.dead_clicks, page.js_errors]
        end
      end
    end

    private

    def shares_of(field)
      counts = Hash.new(0)
      days.each { |day| day.public_send(field).each { |key, count| counts[key] += count.to_i } }
      total = counts.values.sum
      return [] if total.zero?

      counts.sort_by { |key, count| [-count, key] }.map { |key, count| [key, count, count.fdiv(total)] }
    end
  end
end
