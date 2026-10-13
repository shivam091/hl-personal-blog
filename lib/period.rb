# encoding: UTF-8

# Daily figures only mean something over a span of days, so a report always
# covers one rather than being empty until dates are picked.
class Period
  # Months stop at 16 because Google keeps no more.
  PRESETS = [:today, 1, 7, 28, :this_week, :this_month, :this_quarter, :last_quarter, :this_year, *[3, 6, 8, 12, 16].map { |months| :"last_#{months}_months" }].freeze
  MONTHS = /\Alast_(\d+)_months\z/
  # The blog has no earlier data, so all time starts here.
  START = Date.new(2026, 6, 1)
  DEFAULT_DAYS = 28
  # A week back keeps weekends lined up with weekends; a year back takes out
  # seasonality; another country isolates the audience from the time.
  COMPARES = {
    "previous" => "Previous period",
    "week" => "Same period last week",
    "month" => "Same period last month",
    "year" => "Same period last year",
    "custom" => "Custom range",
    "country" => "Another country",
    "off" => "Off"
  }.freeze
  DEFAULT_COMPARE = "previous"

  attr_reader :from, :to, :default_days, :compare, :compare_country, :compare_from, :compare_to, :country

  def initialize(params, default_days: DEFAULT_DAYS, today: Date.current, countries: false, country: nil)
    @default_days = default_days
    @today = today
    @countries = countries
    @country = country
    @compare = params[:compare].presence_in(COMPARES.keys) || DEFAULT_COMPARE
    @compare_country = params[:vs].to_s.upcase if @compare == "country"
    # Only pages filtered by country can draw one's figures, and a country
    # has to be named to be compared with.
    @compare = DEFAULT_COMPARE if @compare == "country" && !(countries && @compare_country&.match?(/\A[A-Z]{2}\z/))
    @compare_country = nil unless @compare == "country"
    if @compare == "custom"
      @compare_from, @compare_to = parse(params[:vs_from]), parse(params[:vs_to])
      @compare_from, @compare_to = @compare_to, @compare_from if @compare_from && @compare_to && @compare_from > @compare_to
    end
    # Both ends have to be picked to be compared with.
    @compare = DEFAULT_COMPARE if @compare == "custom" && !(@compare_from && @compare_to)
    @to = parse(params[:to]) || last_full_day
    @from = parse(params[:from]) || @to - (default_days - 1)
    @from, @to = @to, @from if @from > @to
  end

  # Cached figures are keyed on this, as a compared country's share its dates.
  def key
    [from, to, country]
  end

  def countries?
    @countries
  end

  def apply(scope)
    scope.where(date: from..to)
  end

  def days
    (to - from).to_i + 1
  end

  # A whole calendar year, quarter or month is compared with the one before
  # whatever its length, so days are not counted back.
  def previous
    return Period.new({from: from.iso8601, to: to.iso8601}, default_days: default_days, today: @today, country: compare_country) if compare_countries?
    return Period.new({from: compare_from.iso8601, to: compare_to.iso8601}, default_days: default_days, today: @today) if compare_custom?
    return Period.new({from: (from - 7).iso8601, to: (to - 7).iso8601}, default_days: default_days, today: @today) if week_on_week?
    return Period.new({from: from.prev_year.iso8601, to: to.prev_year.iso8601}, default_days: default_days, today: @today) if year_on_year? || year_so_far?
    return Period.new({from: month_back(from).iso8601, to: month_back(to).iso8601}, default_days: default_days, today: @today) if month_on_month?
    # The days just before a week so far are last week's end, usually a weekend, so they aren't like for like.
    return Period.new({from: (from - 7).iso8601, to: (to - 7).iso8601}, default_days: default_days, today: @today) if preset?(:this_week)

    before = from - 1
    {beginning_of_year: :end_of_year, beginning_of_quarter: :end_of_quarter, beginning_of_month: :end_of_month}.each do |start, finish|
      if from == from.public_send(start) && to == from.public_send(finish)
        return Period.new({from: before.public_send(start).iso8601, to: before.iso8601}, default_days: default_days, today: @today)
      end
    end

    Period.new({from: (from - days).iso8601, to: (from - 1).iso8601}, default_days: default_days, today: @today)
  end

  class << self
    def months(preset)
      preset.to_s[MONTHS, 1].to_i
    end

    # Named as Google names it, so it reads the same as in Google's reports.
    def preset_label(preset)
      case preset
      when :today then "Today"
      when 1 then "Yesterday"
      when :this_week then "This week"
      when :this_month then "This month"
      when :this_quarter then "This quarter"
      when :last_quarter then "Last quarter"
      when :this_year then "This year"
      when :all_time then "All time"
      when MONTHS then "Last #{months(preset)} months"
      else "#{preset} days"
      end
    end
  end

  def preset?(preset)
    [from, to] == preset_range(preset)
  end

  def custom?
    preset.nil?
  end

  def preset
    [*PRESETS, :all_time].find { |preset| preset?(preset) }
  end

  def previous_with(compare)
    Period.new({from: from.iso8601, to: to.iso8601, compare: compare, vs_from: compare_from&.iso8601, vs_to: compare_to&.iso8601}, default_days: default_days, today: @today).previous
  end

  def compare?
    compare != "off"
  end

  def year_on_year?
    compare == "year"
  end

  def week_on_week?
    compare == "week"
  end

  def month_on_month?
    compare == "month"
  end

  def compare_countries?
    compare == "country"
  end

  def compare_custom?
    compare == "custom"
  end

  # The default is left out so URLs stay clean.
  def query
    (preset?(default_days) ? {} : {from: from.iso8601, to: to.iso8601}).merge(compare_query)
  end

  def preset_query(preset)
    return compare_query if preset == default_days

    from, to = preset_range(preset)
    {from: from.iso8601, to: to.iso8601, **compare_query}
  end

  def compare_query
    return {} if compare == DEFAULT_COMPARE
    return {compare: compare, vs: compare_country} if compare_countries?
    return {compare: compare, vs_from: compare_from.iso8601, vs_to: compare_to.iso8601} if compare_custom?

    {compare: compare}
  end

  # Today's figures are still coming in, so they would read as a drop against a full day.
  def last_full_day
    @today - 1
  end

  def to_s
    return country if country

    from == to ? I18n.l(from) : "#{I18n.l(from)} – #{I18n.l(to)}"
  end

  private

  # The year so far is set against the same days a year earlier, since the
  # stretch just before it is the end of the last year, not like for like. A
  # whole year is left to be compared with the one before.
  def year_so_far?
    preset?(:this_year) && to != to.end_of_year
  end

  # This week, month, quarter and year run to yesterday, so on their first day they're
  # still the ones just ended.
  def preset_range(preset)
    case preset
    when :today then [@today, @today]
    when :this_week then [last_full_day.beginning_of_week, last_full_day]
    when :this_month then [last_full_day.beginning_of_month, last_full_day]
    when :this_quarter then [last_full_day.beginning_of_quarter, last_full_day]
    when :this_year then [last_full_day.beginning_of_year, last_full_day]
    when :all_time then [START, last_full_day]
    when :last_quarter
      ended = last_full_day.beginning_of_quarter - 1
      [ended.beginning_of_quarter, ended]
    when MONTHS then [last_full_day.months_ago(self.class.months(preset)) + 1, last_full_day]
    else [last_full_day - (preset - 1), last_full_day]
    end
  end

  # A 31st has no match in a shorter month, so it falls back to that month's
  # last day, as does any month's last day, so 1–30 April is set against all
  # of March rather than leaving its 31st out.
  def month_back(date)
    date == date.end_of_month ? date.prev_month.end_of_month : date.prev_month
  end

  def parse(value)
    Date.iso8601(value) if value.present?
  rescue Date::Error
    nil
  end
end
