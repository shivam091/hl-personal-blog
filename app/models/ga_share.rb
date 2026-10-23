# encoding: UTF-8

# GA's share of the blog's views over a period beside its usual share, so a drop in GA's
# figures can be told from the gap readers' choices always leave.
class GaShare
  attr_reader :period

  def initialize(period)
    @period = period
  end

  def share
    return @share if defined?(@share)

    @share = ConsentSnapshot.ga_share(period)
  end

  # The days before the period first, so a drop running through it can't make itself the usual;
  # failing those, the period's own last days, which still stand out a single bad day.
  def usual
    return @usual if defined?(@usual)

    @usual = ConsentSnapshot.usual(:ga_ratio, period.from) ||
      (@trailing = ConsentSnapshot.usual(:ga_ratio, period.to + 1))
  end

  def usual_basis
    return unless usual

    @trailing ? "its last #{Anomalies::CONSENT_BASELINE_DAYS} days, as too few days before it are stored" :
      "the #{Anomalies::CONSENT_BASELINE_DAYS} days before it"
  end

  def any?
    !share.nil? && !usual.nil?
  end

  # Nil where the blog's own count is, so a day without one breaks the expected line rather than dropping it to zero.
  def expected(views)
    views.map { |count| (count * usual).round unless count.nil? } if usual
  end
end
