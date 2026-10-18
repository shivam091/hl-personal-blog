# encoding: UTF-8

module Google
  module Recaptcha
    # Kept for longer than Google's own console holds, so a score threshold
    # can be judged on whom it would turn away.
    class StatsController < ApplicationController
      # Requests are worked out from the score buckets, so only the date can
      # be sorted on in the database.
      SORT_COLUMNS = {"date" => "desc"}.freeze

      def index
        @period = Period.new(params)
        @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :date)
        stats = @sorting.apply(@period.apply(Stat.all))

        respond_to do |format|
          format.html do
            @pagination = Pagination.new(stats, params)
            @stats = @pagination.records
            period_stats = @period.apply(Stat.all).to_a
            @summary = summary(period_stats)
            @report = Report.new(period_stats, period: @period, action: params[:recaptcha_action])
            # Only once a comparison is picked, and not with a period from
            # before the first sync, which would read as a jump from zero.
            @previous_summary = summary(@period.previous.apply(Stat.all).to_a) if @period.compare? && Stat.where(:date.lte => @period.previous.from).exists?
          end
          format.csv do
            actions = params[:export] == "actions"
            send_csv actions ? Stat.actions_csv(stats) : Stat.to_csv(stats),
              filename: "recaptcha-scores#{"-by-action" if actions}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
              detail: "#{actions ? "Scores by action" : "Daily scores"}, #{@period}"
          end
        end
      end

      # Google returns every day it still holds on each call, so there's no
      # range of days to choose.
      def sync
        SyncRequest.enqueue("recaptcha_metrics")
        redirect_to google_recaptcha_stats_path,
          notice: "Syncing reCAPTCHA scores in the background. Refresh in a moment to see the latest days."
      end

      private

      # Added up in Ruby, since a period holds at most a few hundred days.
      def summary(stats)
        requests = stats.sum(&:requests)
        weighted = stats.sum { |stat| stat.average_score.to_f * stat.requests }
        GroupedScope::Row.new(
          "requests" => requests,
          "low_score_share" => (stats.sum(&:low_score_requests).fdiv(requests) if requests.positive?),
          "average_score" => (weighted / requests if requests.positive?),
          "failed_challenges" => stats.sum { |stat| stat.challenges["failed"].to_i }
        )
      end
    end
  end
end
