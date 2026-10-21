# encoding: UTF-8

# One page's consent split and the share of its views GA lost, put down to causes the way the site's
# snapshots are, so a page losing more than the rest can be told apart from one whose readers decline more.
class PageConsent
  # The frontend's states, named as a reader would; "unset" is a view counted before they were told apart.
  STATES = {
    "granted" => "Granted", "denied" => "Denied", "pending" => "Pending", "default" => "No banner needed", "unset" => "Unknown"
  }.freeze

  attr_reader :page_view, :period, :page_gap

  def initialize(page_view, period, analytics: Google::Analytics::Summary.new(period), page_gap: PageGap.new(period, analytics: analytics))
    @page_view = page_view
    @period = period
    @analytics = analytics
    @page_gap = page_gap
  end

  # A state with no views is left out, so the doughnut's list names only what readers actually did.
  def states
    counts = page_view.consent_within(period)
    STATES.filter_map { |key, name| [name, counts[key]] if counts[key].positive? }.to_h
  end

  def any?
    states.any?
  end

  # Nil on a page GA has nothing for, so the card says so rather than showing GA missing every view.
  def row
    return @row if defined?(@row)

    @row = page_gap.rows.find { |candidate| candidate.slug == page_view.slug }
  end

  def percent
    row&.percent
  end

  def median_percent
    page_gap.median_percent
  end

  def flagged?
    row&.flagged || false
  end

  # Only over the days the page's consent split is known, as a day without it can't be put down to anything.
  def causes
    @causes ||= ConsentGap::CAUSES.each_key.to_h { |cause| [cause, explained_days.sum { |day| day.public_send(cause).to_i }] }
  end

  # Only once every day compared could be explained, as the gap is the period's and the causes would
  # otherwise be set against more days than they cover; nil too when the causes find more than the gap.
  def unexplained
    return unless row && complete?

    rest = row.gap - causes.values.sum
    rest unless rest.negative?
  end

  def complete?
    days.any? && explained_days.size == days.size
  end

  # GA counting as many as the blog or more leaves nothing to put down to a cause.
  def gap?
    !row.nil? && row.gap.positive?
  end

  def days_explained
    explained_days.size
  end

  def days_compared
    days.size
  end

  private

  # GA's views aren't kept per page by day, so 0 stands in for them: only the causes are read, which
  # depend on the blog's own tallies alone.
  def days
    @days ||= begin
      views_by_day = page_view.views_by_day
      @analytics.days_with_data.filter_map do |date|
        day = date.iso8601
        views = views_by_day[day].to_i
        next unless views.positive?

        ConsentSnapshot.compose(ConsentSnapshot::Inputs.new(date: date, first_party: views, analytics: 0, states: page_view.consent_by_day[day],
          ga: page_view.ga_by_day[day], suspects: page_view.suspect_by_day[day], banner: nil))
      end
    end
  end

  def explained_days
    days.select(&:split_recorded)
  end
end
