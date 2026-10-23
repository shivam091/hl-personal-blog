# encoding: UTF-8

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
    @previous = BlogStats::METRICS.index_with { |metric| @stats.compared_by_country(metric) } if @period.compare?
    @country_metric = CountryMetric.new(params[:by].presence_in(COUNTRY_METRICS) || COUNTRY_METRICS.first)
    @granularity = ChartGranularity.new(params, period: @period)
    @lifetime_hits = PageView.hit_totals
    # Lifetime figures are all there is for devices and referrers until they
    # are dated.
    @lifetime_views = PageView.only(:devices, :referrers, :devicesByDay, :referrersByDay).to_a unless @stats.breakdowns_tracked_since
    @latest_messages = Message.order(created_at: :desc).limit(5).to_a
    @latest_subscribers = NewsletterSubscriber.order(subscribed_at: :desc).limit(5).to_a
    @coverage = IndexCoverage.new
    @content = ContentStats.new(@stats, search: @search, coverage: @coverage)
    @syncs = SyncRequest.freshness
    @anomalies = Anomalies.new
    @campaigns = PageView.campaigns_within(@period)
    @published = FeedEntry.published_names(@period)
  end
end
