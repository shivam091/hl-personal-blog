# encoding: UTF-8

# Pages answering the same question for a chosen period and country read
# both from the URL the same way, so a link between them keeps the selection.
module BlogStatsFilters
  extend ActiveSupport::Concern

  private

  def load_blog_stats
    @period = Period.new(params, countries: true)
    @stats = BlogStats.new(@period, country: requested_country)
    # The normalised code, so a lowercase one in a typed URL still selects
    # its option.
    @filtering = Filtering.new({country: @stats.country}, fields: [country_field])
  end

  def load_google_summaries
    @search = Google::SearchConsole::Summary.new(@period, country: @stats.country)
    @ai = Google::SearchConsole::GenerativeAiSummary.new(@period)
    @analytics = Google::Analytics::Summary.new(@period, country: @stats.country)
    @recaptcha = Google::Recaptcha::Summary.new(@period)
  end

  # Only once each source has synced, so an unsynced one doesn't read as
  # every country getting nothing from it.
  def funnel_extras
    {
      search_clicks: (@search.countries.transform_values(&:clicks) if @search.any?),
      analytics_views: (@analytics.countries if @analytics.any?)
    }.compact
  end

  # Checked by shape before the stats load, since the list of countries to
  # check it against comes from the stats themselves.
  def requested_country
    code = params[:country].to_s.upcase
    code if code.match?(/\A[A-Z]{2}\z/)
  end

  def country_field
    codes = (@stats.countries | [@stats.country].compact).sort
    Filtering::Select.new(:country, field: :country, label: "Country", blank_label: "All countries", choices: codes.to_h { |code| [code, helpers.country_label(code)] })
  end
end
