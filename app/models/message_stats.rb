# encoding: UTF-8

# Contact messages read against the admin's own verdicts, so the score the
# form trusts can be judged on what actually got through, and whether
# Google is being told about it.
class MessageStats
  # Tenths, as Enterprise scores in tenths, so each band holds one score.
  BANDS = (0..9).map { |tenth| tenth / 10.0 }.freeze
  # Where the frontend turns messages away, so only higher scores are ever
  # seen here and a stricter threshold can be tried against them.
  FORM_THRESHOLD = 0.5
  THRESHOLDS = [0.5, 0.6, 0.7, 0.8, 0.9].freeze
  # Past three months a day's bar is too thin to read, so bars become weeks.
  MAX_DAILY_BARS = 92
  WAITING_LIMIT = 10
  TOP_LIMIT = 10
  CSV_HEADERS = [
    "Sent", "Name", "Email", "Country", "reCAPTCHA score", "Enterprise assessment",
    "Verdict", "Reported to Google", "Report error"
  ].freeze

  Row = Struct.new(:message, :review, keyword_init: true) do
    def verdict
      review&.verdict
    end

    def score
      message.recaptcha_score
    end

    def assessed?
      message.recaptcha_assessment.present?
    end

    # Each message ends in one of these, so the counts add up to the total.
    def feedback
      if review.nil? then :unmarked
      elsif review.annotated_at then :reported
      elsif !assessed? then :unreportable
      elsif review.annotation_error then :failed
      else :sending
      end
    end
  end

  Band = Struct.new(:score, :messages, :genuine, :spam, :unmarked, keyword_init: true) do
    def label
      format("%.1f", score)
    end

    def spam_share
      marked = genuine + spam
      spam.fdiv(marked) if marked.positive?
    end
  end

  Threshold = Struct.new(:score, :blocked, :genuine_lost, :spam_caught, :spam_through, keyword_init: true) do
    def current?
      score == FORM_THRESHOLD
    end
  end

  Sender = Struct.new(:email, :name, :messages, :last_sent_at, :genuine, :spam, :subscriber, keyword_init: true)
  CountryRow = Struct.new(:country, :messages, :genuine, :spam, :average_score, keyword_init: true) do
    def spam_share
      marked = genuine + spam
      spam.fdiv(marked) if marked.positive?
    end
  end

  attr_reader :period, :country, :by

  def initialize(period, country: nil, by: nil)
    @period = period
    @country = country
    @by = by
  end

  # Cut the same way, so a figure and the one it's judged against can't
  # differ in anything but the dates.
  def previous
    @previous ||= self.class.new(period.previous, country: country, by: by)
  end

  def rows
    @rows ||= load_rows(period)
  end

  def to_csv
    CSV.generate do |csv|
      csv << CSV_HEADERS
      rows.each do |row|
        message = row.message
        csv << [
          message.created_at&.utc&.iso8601(3),
          message.name,
          message.email,
          message.country,
          message.recaptcha_score,
          message.recaptcha_assessment,
          row.review&.label,
          row.review&.annotated_at&.utc&.iso8601(3),
          row.review&.annotation_error
        ]
      end
    end
  end

  def any?
    rows.any?
  end

  def total(within = period)
    within == period ? rows.size : messages_in(within).count
  end

  def count(verdict)
    rows.count { |row| row.verdict == verdict }
  end

  def unmarked
    rows.count { |row| row.review.nil? }
  end

  def spam_share
    marked = count("spam") + count("genuine")
    count("spam").fdiv(marked) if marked.positive?
  end

  def average_score
    scores = rows.filter_map(&:score)
    scores.sum / scores.size if scores.any?
  end

  def assessed
    rows.count(&:assessed?)
  end

  def feedback
    rows.map(&:feedback).tally
  end

  # Errors other than a missing assessment, which isn't a fault but a
  # message from before Enterprise.
  def feedback_errors
    rows.select do |row|
      row.feedback == :failed
    end.map do |row|
      row.review.annotation_error
    end.tally.sort_by { |_, count| -count }
  end

  def last_assessed_at
    rows.select(&:assessed?).filter_map { |row| row.message.created_at }.max
  end

  def last_reported_at
    rows.filter_map { |row| row.review&.annotated_at }.max
  end

  # What was picked, else the widest bars that stay readable.
  def per
    by&.to_sym || (period.days > MAX_DAILY_BARS ? :week : :day)
  end

  # A key per day (or week) of the period, so empty days show as gaps in
  # the run rather than being skipped.
  def timeline
    bucket = ChartGranularity::BUCKETS.fetch(per.to_s)
    keys = (period.from..period.to).map(&bucket).uniq
    counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    rows.each do |row|
      day = row.message.created_at&.in_time_zone&.to_date
      next unless day

      counts[bucket.(day)][row.verdict || "unmarked"] += 1
    end
    [
      keys,
      %w[genuine spam unmarked].to_h { |verdict| [verdict, keys.map { |key| counts[key][verdict] }] }
    ]
  end

  def bands
    by_band = rows.select(&:score).group_by { |row| band_of(row.score) }
    BANDS.filter_map do |score|
      band_rows = by_band.fetch(score, [])
      next if band_rows.empty? && score < FORM_THRESHOLD

      Band.new(
        score: score,
        messages: band_rows.size,
        genuine: band_rows.count { |row| row.verdict == "genuine" },
        spam: band_rows.count { |row| row.verdict == "spam" },
        unmarked: band_rows.count { |row| row.review.nil? }
      )
    end
  end

  # What a stricter form would have done to the messages already marked, so
  # a threshold is chosen on real messages rather than on a guess.
  def thresholds
    scored = rows.select(&:score)
    THRESHOLDS.map do |threshold|
      below = scored.select { |row| row.score < threshold - 1e-9 }
      Threshold.new(
        score: threshold,
        blocked: below.size,
        genuine_lost: below.count { |row| row.verdict == "genuine" },
        spam_caught: below.count { |row| row.verdict == "spam" },
        spam_through: scored.count { |row| row.verdict == "spam" && row.score >= threshold - 1e-9 }
      )
    end
  end

  # Oldest first, so the message kept waiting longest is answered first.
  def waiting(limit: WAITING_LIMIT)
    rows.select do |row|
      row.review.nil?
    end.sort_by do |row|
      row.message.created_at || Time.current
    end.first(limit).map(&:message)
  end

  def waiting_count
    unmarked
  end

  # Someone writing again is either keen or a spammer, and the verdicts so
  # far say which.
  def repeat_senders(limit: TOP_LIMIT)
    groups = rows
               .group_by { |row| row.message.email.to_s.downcase }
               .select { |email, group| email.present? && group.size > 1 }
               .sort_by { |email, group| [-group.size, email] }
               .first(limit)
    # One query for all of them, and only for the senders that are shown.
    subscribers = NewsletterSubscriber
                    .where(:email.in => groups.map { |email, _| /\A#{Regexp.escape(email)}\z/i })
                    .index_by { |subscriber| subscriber.email.to_s.downcase }

    groups.map do |email, group|
      latest = group.max_by { |row| row.message.created_at || Time.at(0) }
      Sender.new(
        email: email,
        name: latest.message.name,
        messages: group.size,
        last_sent_at: latest.message.created_at,
        genuine: group.count { |row| row.verdict == "genuine" },
        spam: group.count { |row| row.verdict == "spam" },
        subscriber: subscribers[email]
      )
    end
  end

  def by_country(limit: TOP_LIMIT)
    rows.group_by do |row|
      row.message.country.presence&.upcase || BlogStats::UNKNOWN_COUNTRY
    end.map do |code, group|
      scores = group.filter_map(&:score)
      CountryRow.new(
        country: code,
        messages: group.size,
        genuine: group.count { |row| row.verdict == "genuine" },
        spam: group.count { |row| row.verdict == "spam" },
        average_score: (scores.sum / scores.size if scores.any?)
      )
    end.sort_by { |row| [-row.messages, row.country] }.then { |sorted| limit ? sorted.first(limit) : sorted }
  end

  private

  def messages_in(within)
    messages = Message.where(
      created_at: within.from.in_time_zone.beginning_of_day..within.to.in_time_zone.end_of_day
    )
    code = within.country || country
    code ? messages.where(country: /\A#{Regexp.escape(code)}\z/i) : messages
  end

  def load_rows(within)
    messages = messages_in(within).order(created_at: :desc).to_a
    reviews = MessageReview.for(messages)
    messages.map { |message| Row.new(message: message, review: reviews[message.id]) }
  end

  # Nudged up first, so 0.7 stored as 0.69999… still lands in its own band.
  def band_of(score)
    ((score.to_f * 10) + 1e-9).floor.clamp(0, 9) / 10.0
  end
end
