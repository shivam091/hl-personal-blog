# encoding: UTF-8

# One IST day's reconciliation of the blog's own views against GA's, kept so
# the history survives GA revising or sampling its figures later, and so a
# sudden change can be judged against days that were already settled.
class ConsentSnapshot
  include Mongoid::Document
  include Mongoid::Timestamps

  # Below this many views, a day's ratios are a handful of readers' worth of noise.
  MIN_VIEWS = 50

  # Counts the report adds up; the others are ratios, kept so they can be read without redoing the sums. "default"
  # is the frontend's word for readers needing no banner; Mongoid keeps that name for its own use, so it is stored as automatic.
  COUNTS = %i[
    first_party analytics granted denied pending automatic unset loaded blocked unknown datacentre
    shown accepted declined no_answer
  ].freeze
  # What each part of the gap is put down to, already scaled to the readers GA could have seen.
  BUCKETS = %i[denied_gap pending_gap blocked_gap unknown_gap datacentre_gap].freeze

  field :day, type: String
  COUNTS.each { |name| field name, type: Integer }
  BUCKETS.each { |name| field name, type: Integer }
  field :gap, type: Integer
  field :remainder, type: Integer
  field :ga_ratio, type: Float
  field :loaded_share, type: Float
  field :denied_share, type: Float
  field :pending_share, type: Float
  field :acceptance_rate, type: Float
  field :banner_per_pending, type: Float
  # Whether each source had been recorded on the day, so a missing figure reads as unknown, not as none.
  field :split_recorded, type: Boolean, default: false
  field :ga_recorded, type: Boolean, default: false
  field :suspects_recorded, type: Boolean, default: false

  index({day: 1}, {unique: true})

  validates :day, presence: true

  # The day's inputs, each already a plain hash or figure, so a snapshot and a live day are worked out by one routine.
  Inputs = Struct.new(:date, :first_party, :analytics, :states, :ga, :suspects, :banner, keyword_init: true)

  class << self
    # Unsaved, so the report can show a day that hasn't been snapshotted yet exactly as it will be stored.
    def compose(inputs)
      new(compose_attributes(inputs))
    end

    # Idempotent, and a figure GA hasn't given yet never wipes one an earlier run kept.
    def record(inputs)
      attributes = compose_attributes(inputs)
      day = attributes[:day]
      existing = where(day: day).first
      attributes = keep_known(existing, attributes) if existing
      now = Time.current
      where(day: day).find_one_and_update(
        {"$set" => attributes.merge(updated_at: now), "$setOnInsert" => {created_at: now}},
        upsert: true, return_document: :after
      )
    end

    # Keyed by ISO day, so the report can tell a stored day from one it has to work out now.
    def stored(period)
      where(:day.gte => period.from.iso8601, :day.lte => period.to.iso8601).index_by(&:day)
    end

    # Summed over the days before dividing, so a busy day weighs as much as its views; days GA has no
    # figure for are left out of both sides, or they would read as GA missing every view.
    def ga_share(period)
      days = stored(period).values.reject { |snapshot| snapshot.analytics.nil? }
      views = days.sum { |snapshot| snapshot.first_party.to_i }
      days.sum(&:analytics).fdiv(views) if views >= MIN_VIEWS
    end

    private

    def compose_attributes(inputs)
      states = inputs.states || {}
      ga = inputs.ga || {}
      suspects = inputs.suspects || {}
      banner = inputs.banner
      precise = ConsentSnapshot.precise?(states)

      attributes = {
        day: inputs.date.iso8601, first_party: inputs.first_party, analytics: inputs.analytics,
        granted: states["granted"].to_i, denied: states["denied"].to_i, pending: states["pending"].to_i,
        automatic: states["default"].to_i, unset: states["unset"].to_i,
        loaded: ga["loaded"].to_i, blocked: ga["blocked"].to_i, datacentre: suspects["datacentre"].to_i,
        split_recorded: precise, ga_recorded: ga.values.sum(&:to_i).positive?, suspects_recorded: suspects.any?,
        shown: banner&.shown.to_i, accepted: banner&.granted.to_i, declined: banner&.denied.to_i, no_answer: banner&.no_answer.to_i
      }
      attributes[:gap] = inputs.first_party.to_i - inputs.analytics unless inputs.analytics.nil?
      attributes[:unknown] = [inputs.first_party.to_i - attributes[:loaded] - attributes[:blocked], 0].max if attributes[:ga_recorded]
      attributes.merge!(buckets(attributes, precise)) if precise && inputs.analytics
      attributes.merge(ratios(attributes))
    end

    # Readers who declined or hadn't answered are invisible to GA whatever else happens to them, so a
    # blocked, undetected or datacentre view only counts against GA for the share who weren't.
    def buckets(attributes, precise)
      total = attributes[:granted] + attributes[:denied] + attributes[:pending] + attributes[:automatic]
      visible = total.positive? ? (attributes[:granted] + attributes[:automatic]).fdiv(total) : 1.0
      found = {denied_gap: attributes[:denied], pending_gap: attributes[:pending]}
      found[:blocked_gap] = (attributes[:blocked] * visible).round if attributes[:ga_recorded]
      found[:unknown_gap] = (attributes[:unknown] * visible).round if attributes[:ga_recorded]
      found[:datacentre_gap] = (attributes[:datacentre] * visible).round if attributes[:suspects_recorded]
      found.merge(remainder: attributes[:gap] - found.values.sum)
    end

    def ratios(attributes)
      views = attributes[:first_party].to_i
      tracked = attributes[:granted] + attributes[:denied] + attributes[:pending] + attributes[:automatic] + attributes[:unset]
      answered = attributes[:accepted] + attributes[:declined]
      detected = attributes[:loaded] + attributes[:blocked]
      {
        ga_ratio: (attributes[:analytics].fdiv(views) if attributes[:analytics] && views >= MIN_VIEWS),
        loaded_share: (attributes[:loaded].fdiv(detected) if attributes[:ga_recorded] && detected >= MIN_VIEWS),
        denied_share: (attributes[:denied].fdiv(tracked) if attributes[:split_recorded] && tracked >= MIN_VIEWS),
        pending_share: (attributes[:pending].fdiv(tracked) if attributes[:split_recorded] && tracked >= MIN_VIEWS),
        acceptance_rate: (attributes[:accepted].fdiv(answered) if answered.positive?),
        banner_per_pending: (attributes[:shown].fdiv(attributes[:pending]) if attributes[:split_recorded] && attributes[:pending].positive?)
      }
    end

    # GA's figure and what hangs on it stay as they were when a later run finds GA hasn't it yet.
    def keep_known(existing, attributes)
      return attributes unless attributes[:analytics].nil? && existing.analytics

      kept = existing.attributes.slice(*(%w[analytics gap remainder ga_ratio] + BUCKETS.map(&:to_s)))
      attributes.merge(kept.symbolize_keys)
    end
  end

  # A day is split precisely once the frontend told those GA sees from those it doesn't; a day with
  # views still in the old "unset" can't say, so it stays out of every attribution.
  def self.precise?(states)
    states = states || {}
    states["unset"].to_i.zero? && %w[granted denied pending default].sum { |state| states[state].to_i }.positive?
  end

  # Only such a day can be pinned on a cause; any other would read as wholly unexplained.
  def complete?
    split_recorded && !analytics.nil? && !remainder.nil?
  end

  def date
    Date.iso8601(day)
  end
end
