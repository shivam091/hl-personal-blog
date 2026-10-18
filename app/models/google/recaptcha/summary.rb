# encoding: UTF-8

module Google
  module Recaptcha
    # The site's scores beside the contact form's, so a threshold can be
    # judged on whom it turns away and where spam comes from.
    class Summary
      BUCKETS = (0..10).map { |tenth| tenth / 10.0 }.freeze

      attr_reader :period

      def initialize(period)
        @period = period
        @stats = period.apply(Stat.all).to_a
      end

      def any?
        @stats.any?
      end

      def requests
        @stats.sum(&:requests)
      end

      def low_score_share
        requests.positive? ? @stats.sum(&:low_score_requests).fdiv(requests) : nil
      end

      def histogram
        counts = Hash.new(0)
        @stats.each { |stat| stat.scores.each { |bucket| counts[bucket["score"].to_f.round(1)] += bucket["count"].to_i } }
        BUCKETS.to_h { |score| [score, counts[score]] }
      end

      # The form keeps a message's score, so its spread shows how close
      # accepted messages came to being turned away.
      def message_histogram
        counts = messages.filter_map { |_, score| score&.floor(1) }.tally
        BUCKETS.to_h { |score| [score, counts.fetch(score, 0)] }
      end

      # Clusters of low scores from one country are a sign of a spam source
      # rather than of unlucky readers.
      def messages_by_country
        messages.group_by { |code, _| code.presence || BlogStats::UNKNOWN_COUNTRY }.map do |code, rows|
          scores = rows.filter_map(&:last)
          [code, rows.size, (scores.sum / scores.size if scores.any?)]
        end.sort_by { |code, count, _| [-count, code] }
      end

      private

      def messages
        @messages ||= Message.where(created_at: period.from.in_time_zone.beginning_of_day..period.to.in_time_zone.end_of_day)
          .pluck(:country, :recaptcha_score)
      end
    end
  end
end
