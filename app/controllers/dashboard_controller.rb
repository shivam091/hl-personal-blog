# encoding: UTF-8

# Exists so how the blog is doing over a period can be judged before
# opening any single list.
class DashboardController < ApplicationController
  include BlogStatsFilters

  COUNTRY_METRICS = %w[views likes subscribers messages].freeze
  # Shaped like the other list states, so changing the period or country
  # keeps the chosen country metric.
  CountryMetric = Struct.new(:metric) do
    def query
      metric == COUNTRY_METRICS.first ? {} : {by: metric}
    end
  end

  def show
    load_blog_stats
    load_google_summaries
    @funnel_extras = funnel_extras
    @country_metric = CountryMetric.new(params[:by].presence_in(COUNTRY_METRICS) || COUNTRY_METRICS.first)
    @granularity = ChartGranularity.new(params)
    @lifetime_hits = PageView.hit_totals
    # Devices and referrers weren't dated at first, so until they are, the
    # lifetime figures are all there is to show for them.
    @lifetime_views = PageView.only(:devices, :referrers, :devicesByDay, :referrersByDay).to_a unless @stats.breakdowns_tracked_since
    @latest_messages = Message.order(created_at: :desc).limit(5).to_a
    @latest_subscribers = NewsletterSubscriber.order(subscribed_at: :desc).limit(5).to_a
    @coverage = IndexCoverage.new
    @content = ContentStats.new(@stats, search: @search, coverage: @coverage)
    @syncs = SyncRequest.freshness
    @anomalies = Anomalies.new
    @campaigns = PageView.campaigns_within(@period)
    @published = FeedEntry.where(published_at: @period.from.beginning_of_day..@period.to.end_of_day).order(published_at: :asc)
      .only(:_id, :name, :published_at).group_by { |entry| entry.published_at.to_date }.transform_values { |entries| entries.map(&:name) }
  end
end
