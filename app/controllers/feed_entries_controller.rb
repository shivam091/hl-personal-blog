# encoding: UTF-8

# No adding, editing or deleting here because the feed owns the content;
# changes come in by syncing.
class FeedEntriesController < ApplicationController
  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :name, label: "Title contains", placeholder: "e.g. z-index or canvas"),
    # Not `url`: it would clash with url_for's own options.
    Filtering::Contains.new(:link, field: :_id, label: "URL contains", placeholder: "e.g. /tutorial/"),
    Filtering::Reference.new(:tag, field: :tag_ids, label: "Tag", model: Tag),
    Filtering::Reference.new(:category, field: :category_ids, label: "Category", model: Category),
    Filtering::DateRange.new(:published, field: :published_at, label: "Published"),
    Filtering::DateRange.new(:updated, field: :last_modified_at, label: "Updated")
  ].freeze
  TYPE_TABS = Filtering::Tabs.new(:type,
    field: :type,
    label: "Filter by type",
    choices: {"post" => ["Posts", "post"], "tutorial" => ["Tutorials", "tutorial"], "snippet" => ["Snippets", "snippet"], "series" => ["Series", "series"]}
  )
  # Each column starts in the direction most useful for it; newest first by
  # default, the order the feed itself uses.
  SORT_COLUMNS = {"published_at" => "desc", "last_modified_at" => "desc", "name" => "asc", "type" => "asc"}.freeze

  before_action :set_feed_entry, only: %i[show notify resend]

  def index
    @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: TYPE_TABS)
    # Not the default _id: it aliases url, and ordering by both collapses
    # into one key that loses the chosen direction.
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :url)
    entries = @sorting.apply(@filtering.apply(FeedEntry.all))

    respond_to do |format|
      format.html do
        @pagination = Pagination.new(entries, params)
        @feed_entries = @pagination.records.includes(:tags, :categories)
        @tab_counts = @filtering.tab_counts(FeedEntry.all)
        @notified_entries = FeedEntry.recently_notified(@filtering.apply(FeedEntry.all))
      end
      format.csv do
        send_csv FeedEntry.to_csv(entries), filename: "feed-entries-#{Date.current.iso8601}.csv"
      end
    end
  end

  def show
  end

  # So new posts can be pulled in right away.
  def sync
    SyncRequest.enqueue("feed")
    redirect_to feed_entries_path, notice: "Syncing from the Atom feed in the background. Refresh in a moment to see new and updated entries."
  end

  # On demand rather than on every sync, so only entries worth an email are
  # announced. In the background, since each subscriber gets their own copy.
  def notify
    unless @feed_entry.claim_notification!
      return redirect_back_or_to feed_entries_path, alert: "Subscribers can only be notified once about an entry, within #{FeedEntry::NOTIFY_DAYS} days of it being published."
    end

    NotifySubscribersJob.perform_later(@feed_entry.url)
    redirect_back_or_to feed_entries_path, notice: "Emailing #{helpers.pluralize(NewsletterSubscriber.count, "subscriber")} about #{@feed_entry.name} in the background."
  end

  # So a subscriber the last send did reach doesn't get a second copy.
  def resend
    emails = @feed_entry.claim_resend!
    return redirect_back_or_to feed_entry_path(@feed_entry), alert: "There are no undelivered emails to send again." if emails.empty?

    NotifySubscribersJob.perform_later(@feed_entry.url, emails)
    redirect_back_or_to feed_entry_path(@feed_entry), notice: "Sending #{@feed_entry.name} again to #{helpers.pluralize(emails.size, "address", plural: "addresses")} in the background."
  end

  private

  def set_feed_entry
    @feed_entry = FeedEntry.find(params[:id])
  end
end
