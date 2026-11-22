# encoding: UTF-8

class ConsentReportsController < ApplicationController
  include BlogStatsFilters

  # Banners and their answers run to a handful a day, so weeks are shown until days are asked for.
  DEFAULT_GRANULARITY = "week"

  # What was asked for, not what the period allowed, so days forced by a short period don't stick to a longer one.
  GranularityState = Struct.new(:by) do
    def query
      by.nil? || by == DEFAULT_GRANULARITY ? {} : {by: by}
    end
  end

  def show
    load_blog_stats
    @granularity = ChartGranularity.new({by: params[:by].presence || DEFAULT_GRANULARITY}, period: @period)
    @granularity_state = GranularityState.new(params[:by].presence_in(ChartGranularity::BUCKETS.keys))
    @consent = ConsentStats.new(@period, country: @stats.country)
    @analytics = Google::Analytics::Summary.new(@period)
    @first_party_views = first_party_views
    @analytics_views = analytics_views
    @gap = @consent.gap(@first_party_views, @analytics_views) if @analytics.any?
    @decomposition = @consent.decomposition(@first_party_views, @analytics_views) if @analytics.any?
    @published = FeedEntry.published_names(@period)
    @health = @consent.banner_health
    @flag_measures = @consent.flag_measures(@consent.daily_snapshots(@first_party_views, @analytics_views))

    respond_to do |format|
      format.html
      format.csv do
        send_csv @consent.to_csv,
                 filename: "consent-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Consent, #{@period}"
      end
    end
  end

  private

  # Every country, as GA's site-wide views and the consent split aren't cut by one.
  def first_party_views
    @period.from.upto(@period.to).zip(@stats.daily(:views, country: nil)).to_h
  end

  # Left out on days GA hasn't synced, which come back nil.
  def analytics_views
    @period.from.upto(@period.to).zip(@analytics.daily_views).to_h.compact
  end
end
