# encoding: UTF-8

module Google
  module Recaptcha
    class ScoresController < ApplicationController
      # Requests are worked out from the score buckets, so only the date can
      # be sorted on in the database.
      SORT_COLUMNS = {"date" => "desc"}.freeze

      # Must match the action the blog's contact form passes, since Google
      # splits scores by it.
      MESSAGE_ACTION = "contact_form"
      TABS = {nil => "All traffic", MESSAGE_ACTION => "Messages"}.freeze

      def index
        @action = params[:recaptcha_action].presence_in(TABS.keys)
        @period = Period.new(params)
        @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :date)
        stats = @sorting.apply(@period.apply(scope))

        respond_to do |format|
          format.html do
            @pagination = Pagination.new(stats, params)
            @stats = for_action(@pagination.records)
            period_stats = for_action(@period.apply(scope))
            @summary = summary(period_stats)
            # Only once a comparison is picked, and not with a period from
            # before the first sync, which would read as a jump from zero.
            previous_stats = for_action(@period.previous.apply(scope)) if @period.compare? && scope.where(:date.lte => @period.previous.from).exists?
            @previous_summary = summary(previous_stats) if previous_stats
            @report = Report.new(period_stats, period: @period, action: @action, previous: previous_stats)
          end
          format.csv do
            actions = params[:export] == "actions" && @action.nil?
            send_csv actions ? Stat.actions_csv(stats) : Stat.to_csv(for_action(stats)),
              filename: "recaptcha-scores#{"-by-action" if actions}#{"-#{@action}" if @action}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
              detail: "#{actions ? "Scores by action" : "Daily scores"}#{" for #{TABS[@action].downcase}" if @action}, #{@period}"
          end
        end
      end

      # Google returns every day it still holds on each call, so there's no
      # range of days to choose.
      def sync
        SyncRequest.enqueue("recaptcha_metrics")
        redirect_to google_recaptcha_scores_path,
          notice: "Syncing reCAPTCHA scores in the background. Refresh in a moment to see the latest days."
      end

      private

      # Only days Google split the action out for, so a day it didn't isn't
      # read as one without messages.
      def scope
        @action ? Stat.where(:"action_scores.#{@action}".exists => true) : Stat.all
      end

      def for_action(stats)
        @action ? stats.map { |stat| stat.for_action(@action) } : stats.to_a
      end

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
