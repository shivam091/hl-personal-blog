# encoding: UTF-8

# Summed only over the days whose gap can be pinned on a cause, so what is left
# unexplained isn't swollen by days that couldn't say.
class ConsentGap
  # In the order a reader would rule them out, with what each says about how GA lost the view.
  CAUSES = {
    denied_gap: "Declined the banner",
    pending_gap: "Not yet answered the banner",
    blocked_gap: "Ad or tracker blocker",
    unknown_gap: "Left before the tag could be checked",
    datacentre_gap: "Suspected datacentre traffic"
  }.freeze

  attr_reader :snapshots

  # Every day GA has figures for, newest first; only those with the consent split known can be explained.
  def initialize(snapshots)
    @snapshots = snapshots
  end

  def days
    @days ||= snapshots.select(&:complete?)
  end

  def any?
    days.any?
  end

  def first_party
    sum(:first_party)
  end

  def analytics
    sum(:analytics)
  end

  def gap
    sum(:gap)
  end

  def percent
    gap.fdiv(first_party) if first_party.positive?
  end

  # One cause's views, over the days that could say.
  def sum(field)
    days.sum { |day| day.public_send(field).to_i }
  end

  def remainder
    sum(:remainder)
  end

  # Negative when the causes found add up to more than the gap, which is GA counting more than they leave room for.
  def over_counted?
    remainder.negative?
  end

  def remainder_share
    remainder.fdiv(gap) if gap.positive?
  end

  def share_of_gap(cause)
    sum(cause).fdiv(gap) if gap.positive?
  end

  # Days that could be explained but hadn't one source recorded, so a cause can read lower than it was.
  def days_missing(recorded)
    days.count { |day| !day.public_send(recorded) }
  end
end
