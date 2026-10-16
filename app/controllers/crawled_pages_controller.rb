# encoding: UTF-8

# Pages come from the sitemap and are read on URL inspection, so only the
# actions taken on one page live here.
class CrawledPagesController < ApplicationController
  # Straight away rather than in a later batch, so a page just published or
  # fixed can be checked while it's being worked on.
  def inspect_url
    page = CrawledPage.find(params[:id])
    result = Google::SearchConsole::UrlInspectionSyncService.new.inspect_now(page)
    if result.errors.any?
      redirect_back_or_to google_search_console_url_inspections_path, alert: "Couldn't inspect #{page}: #{result.errors.to_sentence}", status: :see_other
    else
      redirect_to google_search_console_url_inspection_path(page.reload.url_inspection), notice: "Inspected #{page} just now.", status: :see_other
    end
  end

  # Only remembered, since the request itself is made in Search Console:
  # Google offers no API for it, and resubmitting the sitemap instead is a
  # far weaker nudge. Google can take days to index a page, so the mark is
  # what puts it first in the daily inspections until it's found.
  def request_indexing
    page = CrawledPage.find(params[:id])
    return redirect_back_or_to google_search_console_url_inspections_path, notice: "#{page} is already indexed.", status: :see_other if page.indexed

    # Just this field, so an old row that no longer passes validation is
    # still marked.
    page.set(index_requested_at: Time.current)
    redirect_back_or_to google_search_console_url_inspections_path, status: :see_other,
      notice: "Marked #{page} as requested in Search Console. It's marked indexed once an inspection finds it in Google."
  end

  def sync
    SyncRequest.enqueue("sitemap")
    redirect_to google_search_console_url_inspections_path,
      notice: "Syncing pages from the sitemap in the background. Refresh in a moment to see new and changed pages."
  end
end
