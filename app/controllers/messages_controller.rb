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
        @reviews = MessageReview.for(@messages)
        @tab_counts = @filtering.tab_counts(Message.all)
      end
      format.csv do
        send_csv Message.to_csv(filtered_messages), filename: "messages-#{Date.current.iso8601}.csv"
      end
    end
  end

  def show
    @message = Message.find(params[:id])
    @review = @message.review
  end

  # Back where it was marked, list or message, so a run of messages can be
  # gone through without losing the place.
  def review
    message = Message.find(params[:id])
    verdict = params[:verdict].presence_in(MessageReview::VERDICTS.keys)
    return redirect_back_or_to(message_path(message), alert: "Unknown verdict.") unless verdict

    MessageReview.mark(message, verdict)
    note = message.recaptcha_assessment.present? ? "and reporting it to reCAPTCHA" : "(not reported to reCAPTCHA: no assessment was kept with it)"
    redirect_back_or_to message_path(message), notice: "Marked the message from #{message.name} as #{MessageReview::VERDICTS.dig(verdict, :label).downcase} #{note}."
  end

  private

  def filtered_messages
    @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: SCORE_TABS)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @sorting.apply(@filtering.apply(Message.all))
  end
end
