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
      format.html { load_comparison if @period.compare? }
      format.csv do
        send_csv @consent.to_csv,
                 filename: "consent-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Consent, #{@period}"
      end
    end
  end

  private

  # The banner is split by country, so its answers can be set against another country's; views, GA's figures and
  # the gap aren't, so against another country they are left without an earlier figure.
  def load_comparison
    @previous = @period.previous
    @previous_name = @period.compare_countries? ? helpers.country_label(@period.compare_country) : @previous.to_s
    @consent_before = ConsentStats.new(@previous, country: @previous.country || @stats.country)
    return if @period.compare_countries?

    @states_before = @consent_before.views_by_state
    return unless @analytics.any?

    first_party, analytics = first_party_views(@previous), analytics_views(@previous)
    @gap_before = @consent_before.gap(first_party, analytics)
    @decomposition_before = @consent_before.decomposition(first_party, analytics)
  end

  # Every country, as GA's site-wide views and the consent split aren't cut by one.
  def first_party_views(within = @period)
    within.from.upto(within.to).zip(@stats.daily(:views, within, country: nil)).to_h
  end

  # Left out on days GA hasn't synced, which come back nil.
  def analytics_views(within = @period)
    within.from.upto(within.to).zip(@analytics.daily_views(within)).to_h.compact
  end
end
