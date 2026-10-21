# encoding: UTF-8

# Exists so the audiences that convert can be told apart from the ones that
# only visit.
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
    "country" => "asc"
  }.freeze

  def show
    load_blog_stats
    load_google_summaries
    extras = funnel_extras
    @extras = extras.keys
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :country)
    funnel = @stats.funnel(extras)
    @rows = sorted(funnel.select { |row| @stats.country.nil? || row.country == @stats.country })
    @map_details = map_details(funnel)
    @previous = previous_figures(extras) if @period.compare?

    respond_to do |format|
      format.html
      format.csv do
        send_csv BlogStats::FunnelRow.to_csv(@rows, ai: @ai, previous: @previous),
                 filename: "countries-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Countries, #{@period}"
      end
    end
  end

  private

  # A Google source that hasn't synced is left out rather than shown as nothing.
  def map_details(funnel)
    search = @search.countries if @search.any?
    ai = @ai.countries if @ai&.covered
    funnel.to_h do |row|
      figures = [["Likes", row.likes], ["Subscribers", row.subscribers], ["Messages", row.messages]]
      figures += [["Search clicks", search[row.country]&.clicks.to_i], ["Search impressions", search[row.country]&.impressions.to_i]] if search
      figures << ["AI impressions", ai.fetch(row.country, 0)] if ai
      figures << ["GA views", row.analytics_views.to_i] unless row.analytics_views.nil?
      [row.country, figures]
    end
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
    column = @sorting.column.to_sym
    with_value, without = rows.partition { |row| !row.public_send(column).nil? }
    with_value = with_value.sort_by { |row| [row.public_send(column), row.country] }
    with_value = with_value.reverse if @sorting.direction == "desc"
    with_value + without.sort_by(&:country)
  end
end
