# encoding: UTF-8

class CountryReportsController < ApplicationController
  include BlogStatsFilters

  SORT_COLUMNS = {
    "views" => "desc",
    "likes" => "desc",
    "like_rate" => "desc",
    "subscribers" => "desc",
    "subscriber_rate" => "desc",
    "messages" => "desc",
    "search_clicks" => "desc",
    "analytics_views" => "desc",
    "banners" => "desc",
    "accept_rate" => "desc",
    "country" => "asc"
  }.freeze

  def show
    load_blog_stats
    load_google_summaries
    extras = funnel_extras
    @extras = extras.keys
    @banners = CountryBanners.new(@period)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :country)
    funnel = @stats.funnel(extras)
    @rows = sorted(funnel.select { |row| @stats.country.nil? || row.country == @stats.country })
    @map_details = map_details(funnel)
    @previous = previous_figures(extras) if @period.compare?

    respond_to do |format|
      format.html
      format.csv do
        send_csv BlogStats::FunnelRow.to_csv(@rows, ai: @ai, previous: @previous, banners: @banners),
                 filename: "countries-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Countries, #{@period}"
      end
    end
  end

  private

  # A Google source that hasn't synced is left out rather than shown as nothing.
  # Countries with no activity are absent from the funnel, so they read as zero
  # rather than as having fewer figures than the rest.
  def map_details(funnel)
    search = @search.countries if @search.any?
    ai = @ai.countries if @ai&.covered
    analytics = funnel.any? { |row| !row.analytics_views.nil? }
    names = ["Likes", "Subscribers", "Messages", *(["Search clicks", "Search impressions"] if search), *("AI impressions" if ai), *("GA views" if analytics)]
    details = Hash.new(names.map { |name| [name, 0] })
    funnel.each do |row|
      figures = [["Likes", row.likes], ["Subscribers", row.subscribers], ["Messages", row.messages]]
      figures += [["Search clicks", search[row.country]&.clicks.to_i], ["Search impressions", search[row.country]&.impressions.to_i]] if search
      figures << ["AI impressions", ai.fetch(row.country, 0)] if ai
      figures << ["GA views", row.analytics_views.to_i] unless row.analytics_views.nil?
      details[row.country] = figures
    end
    details
  end

  # Google's figures aren't split by the country being compared with, and
  # an unsynced earlier period would read as every country being new.
  def previous_figures(extras)
    previous = BlogStats::METRICS.index_with { |metric| @stats.compared_by_country(metric) }
    return previous if @period.compare_countries?

    previous[:search_clicks] = @search.countries(@period.previous).transform_values(&:clicks) if extras.key?(:search_clicks) && @search.previous_synced?
    previous[:analytics_views] = @analytics.countries(@period.previous) if extras.key?(:analytics_views) && @analytics.previous?
    previous
  end

  # Rows without a rate (too few views) sort last either way, so a noisy
  # 100% never tops the list.
  def sorted(rows)
    value = sort_value
    with_value, without = rows.partition { |row| !value.(row).nil? }
    with_value = with_value.sort_by { |row| [value.(row), row.country] }
    with_value = with_value.reverse if @sorting.direction == "desc"
    with_value + without.sort_by(&:country)
  end

  # The banner's figures aren't part of the funnel, so they're looked up by country.
  def sort_value
    case @sorting.column
    when "banners" then ->(row) { @banners.shown(row.country) }
    when "accept_rate" then ->(row) { @banners.acceptance_rate(row.country) }
    else ->(row) { row.public_send(@sorting.column) }
    end
  end
end
