# encoding: UTF-8

class ConsentReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    @consent = ConsentStats.new(@period, country: @stats.country)
    @analytics = Google::Analytics::Summary.new(@period)
    @gap = @consent.gap(first_party_views, analytics_views) if @analytics.any?
    @decomposition = @consent.decomposition(first_party_views, analytics_views) if @analytics.any?
    @health = @consent.banner_health

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
