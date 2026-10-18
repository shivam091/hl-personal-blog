# encoding: UTF-8

module Google
  module Recaptcha
    # Exists so a real login being refused, or a run of bot attempts, can be
    # spotted. Read-only because the record is what reCAPTCHA said at the time.
    class AssessmentsController < ApplicationController
      SEARCH_FIELDS = [
        Filtering::Contains.new(:ip, field: :remote_ip, label: "IP contains", placeholder: "e.g. 203.0.113."),
        Filtering::DateRange.new(:time, field: :created_at, label: "Time"),
        Filtering::Contains.new(:reason, field: :reasons, label: "Reason contains", placeholder: "e.g. AUTOMATION"),
        Filtering::Select.new(:password, field: :password_outcome, label: "Password", choices: Assessment::PASSWORD_OUTCOMES),
        Filtering::Contains.new(:user_agent, field: :user_agent, label: "User agent contains", placeholder: "e.g. curl or iPhone")
      ].freeze
      ACCEPTED_TABS = Filtering::Tabs.new(:accepted, field: :accepted, label: "Filter by outcome",
        choices: {"yes" => ["Accepted", true], "no" => ["Rejected", false]})
      SORT_COLUMNS = {"created_at" => "desc", "score" => "asc", "action" => "asc"}.freeze

      def index
        @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: ACCEPTED_TABS)
        @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
        assessments = @sorting.apply(@filtering.apply(Assessment.all))

        respond_to do |format|
          format.html do
            @pagination = Pagination.new(assessments, params)
            @assessments = @pagination.records
            @tab_counts = @filtering.tab_counts(Assessment.all)
            # Over the searched days when some are picked, so the charts
            # cover what the list does.
            @report = LoginReport.new(@filtering.apply(Assessment.all), from: @filtering.values[:time_from], to: @filtering.values[:time_to])
          end
          format.csv do
            send_csv Assessment.to_csv(assessments), filename: "recaptcha-assessments-#{Date.current.iso8601}.csv"
          end
        end
      end

      def show
        @assessment = Assessment.find(params[:id])
      end
    end
  end
end
