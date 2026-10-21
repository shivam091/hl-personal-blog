# encoding: UTF-8

require "csv"

# One queue of entries to update, from every sign that one has gone stale:
# still read though long unchanged, losing the search clicks it had, or
# slipping down the results. One list rather than three, so an entry that
# shows several signs is seen to come first.
class ContentDecay
  # A place lost on average, so a ranking wobbling within a spot isn't
  # called a slip.
  POSITION_SLIP = 1.0
  MIN_AGES = {"3" => "3+ months", "6" => "6+ months", "12" => "1+ year", "24" => "2+ years"}.freeze
  DAYS_PER_MONTH = 30.44
  CSV_HEADERS = [
    "Rank", "URL", "Title", "Type", "Published", "Updated", "Days since update", "Views", "Search clicks",
    "Search clicks before", "Position", "Position before", "Reasons"
  ].freeze

  Row = Struct.new(:item, :reasons, :age_days, :clicks, :previous_clicks, :position, :previous_position, keyword_init: true) do
    def lost_clicks
      previous_clicks ? [previous_clicks - clicks, 0].max : 0
    end
  end

  attr_reader :content, :opportunities

  def initialize(content, opportunities, type: nil, min_age_months: nil, today: Date.current)
    @content = content
    @opportunities = opportunities
    @type = type
    @min_age_days = (min_age_months.to_i * DAYS_PER_MONTH).round if min_age_months.to_i.positive?
    @today = today
  end

  # Only while the period before was synced, and is being compared with,
  # since otherwise every entry would read as having lost nothing.
  def compared?
    period.compare? && opportunities.pages_compared?
  end

  # Most signs first, then what costs most now: search clicks lost, then
  # readers, then time since the last update.
  def rows
    @rows ||= begin
      losing = compared? ? opportunities.losing_pages(limit: nil).index_by(&:page_path) : {}
      now = opportunities.summary.pages
      before = compared? ? opportunities.summary.pages(period.previous) : {}
      content.items.filter_map do |item|
        next if @type && item.type != @type

        age_days = (@today - item.entry.last_modified_at.to_date).to_i
        next if @min_age_days && age_days < @min_age_days

        current, previous = now[item.path], before[item.path]
        reasons = reasons(item, age_days, losing[item.path], current, previous)
        next if reasons.empty?

        Row.new(item: item, reasons: reasons, age_days: age_days, clicks: current&.clicks.to_i, previous_clicks: previous&.clicks,
          position: current&.position, previous_position: previous&.position)
      end.sort_by { |row| [-row.reasons.size, -row.lost_clicks, -row.item.views, -row.age_days, row.item.path] }
    end
  end

  def to_csv
    CSV.generate do |csv|
      csv << CSV_HEADERS
      rows.each.with_index(1) do |row, rank|
        entry = row.item.entry
        csv << [
          rank, entry.url, entry.name, entry.type, entry.published_at&.utc&.iso8601, entry.last_modified_at&.utc&.iso8601,
          row.age_days, row.item.views, row.clicks, row.previous_clicks, row.position&.round(1), row.previous_position&.round(1),
          row.reasons.join("; ")
        ]
      end
    end
  end

  private

  def period
    content.blog_stats.period
  end

  # A slip already behind lost clicks is left to that reason, so one
  # cause isn't counted as two signs.
  def reasons(item, age_days, losing, current, previous)
    reasons = []
    if content.worth_refreshing?(item, today: @today)
      reasons << "Not updated in #{months(age_days)}, still read #{item.views} times"
    end
    reasons << "Lost #{losing.lost} of #{losing.previous_clicks} search clicks: #{losing.cause.downcase}" if losing
    if !losing && slipped?(current, previous)
      reasons << "Slipped from position #{previous.position.round(1)} to #{current.position.round(1)}"
    end
    reasons
  end

  def slipped?(current, previous)
    current&.position && previous&.position && previous.impressions >= Google::SearchConsole::Summary::MIN_IMPRESSIONS &&
      current.position - previous.position >= POSITION_SLIP
  end

  def months(days)
    count = (days / DAYS_PER_MONTH).floor
    count >= 24 ? "#{count / 12} years" : "#{count} months"
  end
end
