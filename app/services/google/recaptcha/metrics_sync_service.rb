# encoding: UTF-8

module Google
  module Recaptcha
    # Google returns every day it still holds, so each run refreshes all of
    # them and nothing needs a date range.
    class MetricsSyncService
      SCOPE = Verifier::SCOPE
      METRICS_URL = "https://recaptchaenterprise.googleapis.com/v1/projects/%{project}/keys/%{key}/metrics"
      CHALLENGE_COUNTS = {"pageloadCount" => "page_loads", "nocaptchaCount" => "no_challenge", "passedCount" => "passed", "failedCount" => "failed"}.freeze

      class << self
        def call(...)
          new(...).call
        end
      end

      # A Google Cloud project, even for keys made at google.com/recaptcha/admin,
      # because Google moved those keys into one (that page links to it).
      def initialize(options = {})
        @project = options.fetch(:project) { Rails.application.credentials.dig(:google, :recaptcha_project_id) }
        @site_key = options.fetch(:site_key) { Rails.application.credentials.dig(:recaptcha, :site_key) }
        @client = options.fetch(:client) { ApiClient.new(scope: SCOPE) }
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        return result.tap { result.errors << "No reCAPTCHA project configured (credentials google.recaptcha_project_id)" } if @project.blank?
        return result.tap { result.errors << "No reCAPTCHA site key configured (credentials recaptcha.site_key)" } if @site_key.blank?

        synced = SyncLock.hold("google/recaptcha/metrics") { Stat.sync(rows, result) }
        result.errors << "reCAPTCHA: another sync is already running, so this one was skipped" unless synced
        result
      rescue ApiClient::Error => e
        result.errors << "reCAPTCHA: #{e.message}"
        result
      end

      private

      # Read by position, because Google gives each metric as a list with one
      # entry per day from startTime rather than dated entries.
      def rows
        metrics = @client.get(format(METRICS_URL, project: ERB::Util.url_encode(@project), key: ERB::Util.url_encode(@site_key)))
        return [] if metrics["startTime"].blank?

        first_day = Time.iso8601(metrics["startTime"]).utc.to_date
        score_days = metrics.fetch("scoreMetrics", [])
        challenge_days = metrics.fetch("challengeMetrics", [])

        Array.new([score_days.size, challenge_days.size].max) do |offset|
          day = score_days[offset] || {}
          {
            date: first_day + offset,
            scores: buckets(day.dig("overallMetrics", "scoreBuckets")),
            action_scores: day.fetch("actionMetrics", {}).transform_values { |action| buckets(action["scoreBuckets"]) },
            challenges: (challenge_days[offset] || {}).slice(*CHALLENGE_COUNTS.keys).to_h { |name, count| [CHALLENGE_COUNTS[name], count.to_i] }
          }
        end
      end

      # Google keys each bucket by its score times 100 ("90" is 0.9), and
      # counts come as strings, since both are 64-bit in the API.
      def buckets(score_buckets)
        (score_buckets || {}).map { |score, count| {"score" => score.to_i / 100.0, "count" => count.to_i} }.sort_by { |bucket| -bucket["score"] }
      end
    end
  end
end
