# encoding: UTF-8

module Google
  module Recaptcha
    # Added up so whether the threshold turns away real logins, and whether
    # one address keeps trying, is read at a glance rather than row by row.
    class LoginReport
      # Long enough to show a run of attempts, short enough that each day
      # keeps a bar wide enough to hover.
      DAYS = 30
      TOP_IPS = 10
      PASSWORD_GROUPS = {"CORRECT_PASSWORD" => "Right password", "INCORRECT_PASSWORD" => "Wrong password", nil => "Not checked"}.freeze

      Address = Struct.new(:ip, :attempts, :rejected, :wrong_passwords, :last_at, keyword_init: true)

      attr_reader :from, :to

      # Plucked rather than loaded, since only a few fields are counted and
      # admin logins are few enough to add up in Ruby.
      def initialize(criteria, from: nil, to: nil, today: Date.current)
        @rows = criteria.pluck(:created_at, :accepted, :score, :password_outcome, :remote_ip)
        @to = to || today
        @from = from || @to - (DAYS - 1)
        @from, @to = @to, @from if @from > @to
      end

      def any?
        @rows.any?
      end

      def attempts
        @rows.size
      end

      def accepted
        @rows.count { |row| row[1] }
      end

      def rejected
        attempts - accepted
      end

      def wrong_passwords
        @rows.count { |row| row[3] == "INCORRECT_PASSWORD" }
      end

      def addresses
        @rows.filter_map { |row| row[4].presence }.uniq.size
      end

      # A day with no attempts is a zero, unlike a sync gap, since every
      # attempt is recorded as it happens.
      def daily
        counts = @rows.each_with_object(Hash.new { |hash, key| hash[key] = [0, 0] }) do |(at, accepted), days|
          next unless at

          days[at.to_date][accepted ? 0 : 1] += 1
        end
        (from..to).map { |date| [date, *counts.fetch(date, [0, 0])] }
      end

      # Floored to tenths as reCAPTCHA buckets them, split by how the password
      # turned out, so a right password scored low is a real login the
      # threshold would refuse.
      def scores_by_password
        counts = @rows.each_with_object(Hash.new(0)) do |(_, _, score, outcome), tally|
          tally[[score.floor(1), PASSWORD_GROUPS.key?(outcome) ? outcome : nil]] += 1 if score
        end
        PASSWORD_GROUPS.to_h do |outcome, _|
          [outcome, Summary::BUCKETS.map { |bucket| counts[[bucket, outcome]] }]
        end
      end

      # Only addresses seen more than once, since a single attempt is no run.
      def repeat_addresses(limit: TOP_IPS)
        @rows.select { |row| row[4].present? }.group_by { |row| row[4] }.filter_map do |ip, rows|
          next if rows.size < 2

          Address.new(ip: ip, attempts: rows.size, rejected: rows.count { |row| !row[1] },
            wrong_passwords: rows.count { |row| row[3] == "INCORRECT_PASSWORD" }, last_at: rows.filter_map(&:first).max)
        end.sort_by { |address| [-address.attempts, -address.rejected, address.ip] }.first(limit)
      end
    end
  end
end
