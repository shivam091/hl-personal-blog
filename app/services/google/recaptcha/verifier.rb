# encoding: UTF-8

module Google
  module Recaptcha
    # So scripted password guessing is turned away before it reaches the
    # admin login. Through reCAPTCHA Enterprise once its project is
    # configured, because only that says why a token scored low and accepts
    # feedback; through the legacy siteverify endpoint until then. Off until a
    # site key and one way of checking are set, so a local setup without them
    # still lets the admin in.
    class Verifier
      VERIFY_URL = "https://www.google.com/recaptcha/api/siteverify"
      ASSESSMENTS_URL = "https://recaptchaenterprise.googleapis.com/v1/projects/%{project}/assessments"
      SCOPE = "https://www.googleapis.com/auth/cloud-platform"
      DEFAULT_MIN_SCORE = 0.5
      # Short, since the admin is left waiting on the login form.
      OPEN_TIMEOUT = 2
      READ_TIMEOUT = 5

      Verdict = Struct.new(:human, :assessment) do
        def human?
          human
        end
      end

      class << self
        def enabled?
          new.enabled?
        end

        def site_key
          new.site_key
        end

        def check(...)
          new.check(...)
        end
      end

      attr_reader :site_key

      def initialize(options = {})
        @site_key = options.fetch(:site_key) { config[:site_key] }
        @secret_key = options.fetch(:secret_key) { config[:secret_key] }
        @min_score = (options.fetch(:min_score) { config[:min_score] }.presence || DEFAULT_MIN_SCORE).to_f
        @project = options.fetch(:project) { Rails.application.credentials.dig(:google, :recaptcha_project_id) }
        @connection = options[:connection]
        @client = options[:client] || ApiClient.new(scope: SCOPE, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, retry_connect: false)
      end

      def enabled?
        @site_key.present? && (enterprise? || @secret_key.present?)
      end

      def enterprise?
        @project.present? && @client.configured?
      end

      # A token from another form (`action`) is refused, so one scored on a
      # gentler page can't be replayed here.
      def check(token, action:, remote_ip: nil, user_agent: nil)
        return Verdict.new(true, nil) unless enabled?
        return reject(nil, "no token") if token.blank?

        assessment = enterprise? ? assess(token, action, remote_ip, user_agent) : siteverify(token, remote_ip)
        assessment.assign_attributes(expected_action: action, remote_ip: remote_ip, user_agent: user_agent)
        reason = rejection_reason(assessment, action)
        assessment.accepted = reason.nil?
        assessment.save
        reason ? reject(assessment, reason) : Verdict.new(true, assessment)
      rescue Faraday::Error, JSON::ParserError, ApiClient::Error => e
        # The password still has to be right and attempts are rate limited, so
        # Google being unreachable or refusing the check shouldn't lock the admin
        # out.
        Rails.logger.warn("reCAPTCHA check skipped, Google unavailable: #{e.message}")
        Verdict.new(true, nil)
      end

      private

      def rejection_reason(assessment, action)
        return "invalid token (#{assessment.invalid_reason})" unless assessment.valid_token
        return "token for #{assessment.action.inspect}, not #{action.inspect}" unless assessment.action == action

        "score #{assessment.score} below #{@min_score}" if assessment.score.to_f < @min_score
      end

      def assess(token, action, remote_ip, user_agent)
        response = @client.post(format(ASSESSMENTS_URL, project: ERB::Util.url_encode(@project)), {
          event: {
            token: token,
            siteKey: @site_key,
            expectedAction: action,
            userIpAddress: remote_ip,
            userAgent: user_agent
          }.compact
        })
        risk = response.fetch("riskAnalysis", {})
        token_properties = response.fetch("tokenProperties", {})
        valid = token_properties["valid"] == true
        Assessment.new(
          name: response["name"],
          score: risk["score"],
          reasons: Array(risk["reasons"]),
          # Valid tokens come with "INVALID_REASON_UNSPECIFIED", which says nothing.
          valid_token: valid,
          invalid_reason: (token_properties["invalidReason"] unless valid),
          action: token_properties["action"],
          hostname: token_properties["hostname"],
          token_created_at: parse_time(token_properties["createTime"])
        )
      end

      def siteverify(token, remote_ip)
        result = JSON.parse(
          connection.post(VERIFY_URL, URI.encode_www_form({secret: @secret_key, response: token, remoteip: remote_ip}.compact)).body
        )
        Assessment.new(
          score: result["score"],
          valid_token: (result["success"] == true),
          invalid_reason: Array(result["error-codes"]).join(", ").presence,
          action: result["action"],
          hostname: result["hostname"],
          token_created_at: parse_time(result["challenge_ts"])
        )
      end

      def parse_time(value)
        Time.iso8601(value) if value.present?
      rescue ArgumentError
        nil
      end

      def reject(assessment, reason)
        Rails.logger.info("reCAPTCHA rejected: #{reason}")
        Verdict.new(false, assessment)
      end

      def connection
        @connection ||= Faraday.new(
          headers: {"Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json"},
          request: {open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT}
        ) do |faraday|
          faraday.use ExternalCallRecorder
          faraday.response :raise_error
        end
      end

      def config
        Rails.application.credentials.recaptcha || {}
      end
    end
  end
end
