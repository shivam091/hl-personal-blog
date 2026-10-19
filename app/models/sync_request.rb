# encoding: UTF-8

# A failed or skipped sync would otherwise leave nothing but a log line; a
# record shows when data last arrived and lets one be run again exactly as
# it was asked for.
class SyncRequest
  include Mongoid::Document
  include Mongoid::Timestamps

  Kind = Struct.new(:key, :section, :source, :page, :enqueue, keyword_init: true)

  # Lambdas, so a kind's job loads only when a sync is enqueued.
  KINDS = [
    Kind.new(key: "feed", section: "Feed entries", source: "Atom feed", page: :feed_entries_path,
      enqueue: ->(request) { SyncFeedJob.perform_later(request_id: request.id.to_s) }),
    Kind.new(key: "sitemap", section: "Crawled pages", source: "Blog sitemap", page: :crawled_pages_path,
      enqueue: ->(request) { SyncSitemapJob.perform_later(request_id: request.id.to_s) }),
    Kind.new(key: "search_console_performance", section: "Search performance", source: "Search Console",
      page: :google_search_console_performance_path,
      enqueue: ->(request) {
        Google::SearchConsole::SyncJob.perform_later(request.days, request.to_date.iso8601, only: ["performance"], request_id: request.id.to_s)
      }),
    Kind.new(key: "search_console_sitemaps", section: "Sitemaps", source: "Search Console", page: :google_search_console_sitemaps_path,
      enqueue: ->(request) { Google::SearchConsole::SyncJob.perform_later(only: ["sitemaps"], request_id: request.id.to_s) }),
    Kind.new(
      key: "sitemap_submission",
      section: "Sitemap submission",
      source: "Search Console",
      page: :google_search_console_sitemaps_path,
      enqueue: ->(request) { Google::SearchConsole::SitemapSubmitJob.perform_later(request_id: request.id.to_s) }
    ),
    Kind.new(key: "url_inspections", section: "URL inspection", source: "Search Console", page: :google_search_console_url_inspections_path,
      enqueue: ->(request) {
        Google::SearchConsole::SyncJob.perform_later(only: ["url_inspections"],
          limit: request.limit || Google::SearchConsole::UrlInspectionSyncService::DEFAULT_LIMIT, request_id: request.id.to_s)
      }),
    Kind.new(key: "analytics", section: "Analytics acquisition, engagement, users & retention", source: "Google Analytics", page: :google_analytics_acquisition_path,
      enqueue: ->(request) { Google::Analytics::SyncJob.perform_later(request.days, request.to_date.iso8601, request_id: request.id.to_s) }),
    Kind.new(key: "analytics_annotations", section: "Analytics annotations", source: "Google Analytics", page: :google_analytics_settings_path,
      enqueue: ->(request) { Google::Analytics::AnnotationJob.perform_later(request_id: request.id.to_s) }),
    Kind.new(key: "recaptcha_metrics", section: "reCAPTCHA scores", source: "reCAPTCHA", page: :google_recaptcha_scores_path,
      enqueue: ->(request) { Google::Recaptcha::MetricsSyncJob.perform_later(request_id: request.id.to_s) }),
    Kind.new(
      key: "mixpanel",
      section: "Mixpanel pages, engagement & frustration",
      source: "Mixpanel",
      page: :mixpanel_report_path,
      enqueue: ->(request) { Mixpanel::SyncJob.perform_later(request.days, request.to_date.iso8601, request_id: request.id.to_s) }
    ),
    Kind.new(
      key: "mixpanel_annotations",
      section: "Mixpanel annotations",
      source: "Mixpanel",
      page: :mixpanel_report_path,
      enqueue: ->(request) { Mixpanel::AnnotationJob.perform_later(request_id: request.id.to_s) }
    ),
    Kind.new(
      key: "mixpanel_lexicon",
      section: "Mixpanel event descriptions",
      source: "Mixpanel",
      page: :mixpanel_report_path,
      enqueue: ->(request) { Mixpanel::LexiconJob.perform_later(request_id: request.id.to_s) }
    )
  ].index_by(&:key).freeze

  TRIGGERS = {"admin" => "Admin", "resync" => "Resync", "rake" => "Rake task", "job" => "Background job"}.freeze
  STATUSES = %w[queued running succeeded partial failed].freeze
  IN_PROGRESS = %w[queued running].freeze
  # A sync with some errors still brought data in, so it counts as a sync.
  COMPLETED = %w[succeeded partial].freeze
  # A run can fail item by item; the first few errors say what went wrong
  # without bloating the document.
  MAX_STORED_ERRORS = 20
  # Longer than any sync takes, so only a lost or crashed run reads as stalled.
  STALE_AFTER = 1.hour

  field :kind, type: String
  field :trigger, type: String, default: "job"
  field :status, type: String, default: "queued"
  field :from_date, type: Date
  field :to_date, type: Date
  field :limit, type: Integer
  field :created_count, type: Integer
  field :updated_count, type: Integer
  field :unchanged_count, type: Integer
  field :error_count, type: Integer, default: 0
  field :error_messages, type: Array, default: []
  field :started_at, type: Time
  field :finished_at, type: Time

  # Sorts carry an _id tiebreaker, which an index without it can't serve.
  index({created_at: -1, _id: 1})
  index({kind: 1, status: 1, finished_at: -1})
  index({kind: 1, created_at: -1, _id: -1})

  validates :kind, inclusion: {in: ->(_) { KINDS.keys }}
  validates :trigger, inclusion: {in: TRIGGERS.keys}
  validates :status, inclusion: {in: STATUSES}

  class << self
    def enqueue(kind, trigger: "admin", **attributes)
      create!(kind: kind, trigger: trigger, **attributes).tap(&:enqueue)
    end

    # So a sync run without a request (a rake task, or a job enqueued
    # elsewhere) is still recorded.
    def track(kind, request_id: nil, trigger: "job", **attributes, &sync)
      request = (where(id: request_id).first if request_id) || create!(kind: kind, trigger: trigger, **attributes)
      request.run(&sync)
    end

    def range(days, ending = Date.current)
      days = days.to_i.clamp(1..)
      {from_date: ending - (days - 1), to_date: ending}
    end

    def last_completed(kind)
      where(kind: kind, :status.in => COMPLETED).order(finished_at: :desc).first
    end

    def latest(kind)
      where(kind: kind).order(created_at: :desc, _id: :desc).first
    end

    def freshness
      KINDS.keys.to_h { |kind| [kind, [last_completed(kind), latest(kind)]] }
    end
  end

  def run
    update!(status: "running", started_at: Time.current)
    result = yield
    update!(
      status: status_for(result),
      finished_at: Time.current,
      created_count: result.created,
      updated_count: result.updated,
      unchanged_count: result.unchanged,
      error_count: result.errors.size,
      error_messages: result.errors.first(MAX_STORED_ERRORS).map(&:to_s)
    )
    result
  rescue StandardError => e
    # Left running, it would read as still in progress until it went stale.
    update!(status: "failed", finished_at: Time.current, error_count: 1, error_messages: ["#{e.class}: #{e.message}"])
    raise
  end

  def enqueue
    kind_info.enqueue.call(self)
  end

  def resync
    self.class.enqueue(kind, trigger: "resync", from_date: from_date, to_date: to_date, limit: limit)
  end

  def kind_info
    KINDS.fetch(kind)
  end

  def section
    kind_info.section
  end

  def source
    kind_info.source
  end

  def trigger_label
    TRIGGERS.fetch(trigger, trigger)
  end

  def days
    (to_date - from_date).to_i + 1 if from_date && to_date
  end

  def duration
    finished_at - started_at if started_at && finished_at
  end

  def rows
    [created_count, updated_count, unchanged_count].compact.sum if finished_at && created_count
  end

  # A queued job is lost when the process restarts (the queue is in
  # memory), and a crash can stop one midway, so an old unfinished request
  # is shown as stalled rather than in progress forever.
  def stalled?
    IN_PROGRESS.include?(status) && updated_at && updated_at < STALE_AFTER.ago
  end

  def in_progress?
    IN_PROGRESS.include?(status) && !stalled?
  end

  def display_status
    stalled? ? "stalled" : status
  end

  def to_s
    "#{section} sync"
  end

  private

  # Same rule as the rake tasks' exit code, so a run can't pass in one and
  # fail in the other.
  def status_for(result)
    return "succeeded" if result.errors.empty?

    result.failed? ? "failed" : "partial"
  end
end
