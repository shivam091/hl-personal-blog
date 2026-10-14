# encoding: UTF-8

# So the audience's growth can be tracked and a subscriber found.
class NewsletterSubscribersController < ApplicationController
  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :email, label: "Email contains", placeholder: "e.g. gmail.com or ada@"),
    Filtering::DateRange.new(:subscribed, field: :subscribed_at, label: "Subscribed")
  ].freeze
  # Newest first by default, since recent signups are what's usually checked.
  SORT_COLUMNS = {"subscribed_at" => "desc", "email" => "asc"}.freeze

  def index
    respond_to do |format|
      format.html do
        subscribers = filtered_newsletter_subscribers
        @pagination = Pagination.new(subscribers, params)
        @newsletter_subscribers = @pagination.records
        @country_counts = NewsletterSubscriber.country_counts(subscribers)
        @weekly_totals = NewsletterSubscriber.weekly_totals(subscribers)
      end
      format.csv do
        send_csv NewsletterSubscriber.to_csv(filtered_newsletter_subscribers), filename: "newsletter-subscribers-#{Date.current.iso8601}.csv"
      end
    end
  end

  def show
    @newsletter_subscriber = NewsletterSubscriber.find(params[:id])
  end

  def destroy
    subscriber = NewsletterSubscriber.find(params[:id])
    subscriber.delete
    redirect_back_or_to newsletter_subscribers_path, notice: "Unsubscribed #{subscriber.email}.", status: :see_other
  end

  private

  def filtered_newsletter_subscribers
    @filtering = Filtering.new(params, fields: SEARCH_FIELDS)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @sorting.apply(@filtering.apply(NewsletterSubscriber.all))
  end
end
