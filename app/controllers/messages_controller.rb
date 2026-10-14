# encoding: UTF-8

# The only place contact-form messages can be read, so none go unanswered.
class MessagesController < ApplicationController
  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :message, label: "Message contains", placeholder: "e.g. collaboration"),
    Filtering::DateRange.new(:sent, field: :created_at, label: "Sent"),
    Filtering::Contains.new(:name, field: :name, label: "Name contains"),
    Filtering::Contains.new(:email, field: :email, label: "Email contains", placeholder: "e.g. gmail.com")
  ].freeze
  # The form rejects scores under 0.5, so stored messages split into ones
  # reCAPTCHA is confident about and borderline ones worth a second look.
  SCORE_TABS = Filtering::Tabs.new(:score, field: :recaptcha_score, label: "Filter by reCAPTCHA score",
    choices: {
      "high" => ["Likely human", 0.7..1.0],
      "borderline" => ["Borderline", 0.0...0.7]
    })
  # Newest first by default, so unanswered messages are on top.
  SORT_COLUMNS = {"created_at" => "desc", "name" => "asc", "email" => "asc", "recaptcha_score" => "desc"}.freeze

  def index
    respond_to do |format|
      format.html do
        @pagination = Pagination.new(filtered_messages, params)
        @messages = @pagination.records.to_a
        @tab_counts = @filtering.tab_counts(Message.all)
      end
      format.csv do
        send_csv Message.to_csv(filtered_messages), filename: "messages-#{Date.current.iso8601}.csv"
      end
    end
  end

  def show
    @message = Message.find(params[:id])
  end

  private

  def filtered_messages
    @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: SCORE_TABS)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @sorting.apply(@filtering.apply(Message.all))
  end
end
