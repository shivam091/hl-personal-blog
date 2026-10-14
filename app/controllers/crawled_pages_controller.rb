# encoding: UTF-8

# Exists so Google crawl state can be corrected by hand and moved in and
# out of spreadsheets in bulk.
class CrawledPagesController < ApplicationController
  # The flash lives in a ~4KB cookie, so a bad import can't flash every error.
  MAX_FLASHED_IMPORT_ERRORS = 10

  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. /tag/ or css-grid"),
    Filtering::DateRange.new(:modified, field: :last_modified_at, label: "Last modified")
  ].freeze
  INDEXED_TABS = Filtering::Tabs.new(:indexed, field: :indexed, label: "Filter by indexed status", choices: {"yes" => ["Indexed", true], "no" => ["Not indexed", false]})

  before_action :set_crawled_page, only: %i[edit update]

  def index
    @layout = ListLayout.find(:crawled_pages)
    @filtering = @layout.filtering(params, fields: SEARCH_FIELDS)
    @sorting = @layout.sorting(params, tiebreaker: :url)
    pages = @sorting.apply(@filtering.apply(CrawledPage.all))

    respond_to do |format|
      format.html do
        @pagination = @layout.pagination(pages, params)
        @crawled_pages = @pagination.records
        @tab_counts = @filtering.tab_counts(CrawledPage.all)
      end
      format.csv do
        send_csv CrawledPage.to_csv(pages),
          filename: "crawled-pages-#{Date.current.iso8601}.csv"
      end
    end
  end

  def new
    @crawled_page = CrawledPage.new
  end

  def create
    @crawled_page = CrawledPage.new(crawled_page_params)

    if @crawled_page.save
      redirect_to crawled_pages_path, notice: "Added #{@crawled_page}."
    else
      render_with_errors :new
    end
  end

  def edit
  end

  def update
    if @crawled_page.update(crawled_page_params)
      redirect_to crawled_pages_path, notice: "Updated #{@crawled_page}."
    else
      render_with_errors :edit
    end
  end

  def import
    file = params[:file]
    unless file.respond_to?(:read)
      return redirect_to crawled_pages_path, alert: "Choose a CSV file to import."
    end

    # Uploads are read as binary, so non-ASCII URLs would break parsing.
    result = CrawledPage.import_csv(file.read.force_encoding(Encoding::UTF_8))
    flash[:notice] = "Imported #{file.original_filename}: #{result.summary}."
    flash[:import_errors] = result.errors.first(MAX_FLASHED_IMPORT_ERRORS) if result.errors.any?
    redirect_to crawled_pages_path
  end

  # URL inspection re-checks only a batch of pages a day, so a change
  # already seen in Search Console can still be recorded straight away.
  def mark_indexed
    mark(indexed: true)
  end

  def mark_not_indexed
    mark(indexed: false)
  end

  # Straight away rather than in a later batch, so a page just published or
  # fixed can be checked while it's being worked on.
  def inspect_url
    page = CrawledPage.find(params[:id])
    result = Google::SearchConsole::UrlInspectionSyncService.new.inspect_now(page)
    if result.errors.any?
      redirect_back_or_to crawled_pages_path, alert: "Couldn't inspect #{page}: #{result.errors.to_sentence}", status: :see_other
    else
      redirect_to google_search_console_url_inspection_path(page.reload.url_inspection), notice: "Inspected #{page} just now.", status: :see_other
    end
  end

  # Only remembered, since the request itself is made in Search Console:
  # Google offers no API for it, and resubmitting the sitemap instead is a
  # far weaker nudge. Google can take days to index a page, so the mark is
  # what puts it first in the daily inspections until it's found.
  def request_indexing
    pages = params[:id] ? [CrawledPage.find(params[:id])] : CrawledPage.where(:_id.in => selected_ids).to_a
    return redirect_back_or_to crawled_pages_path, alert: "Select at least one page to mark as requested.", status: :see_other if pages.empty?

    pages.reject!(&:indexed)
    return redirect_back_or_to crawled_pages_path, notice: "Those pages are already indexed.", status: :see_other if pages.empty?

    now = Time.current
    # Just this field, so an old row that no longer passes validation is
    # still marked.
    pages.each { |page| page.set(index_requested_at: now) }
    redirect_back_or_to crawled_pages_path,
      status: :see_other,
      notice: "Marked #{helpers.pluralize(pages.size, "page")} as requested in Search Console. " \
        "Each is marked indexed once an inspection finds it in Google."
  end

  private

  def mark(indexed:)
    status = indexed ? "indexed" : "not indexed"
    # An indexed page's request has landed, however that was found out.
    changes = {indexed: indexed, updated_at: Time.current, **({index_requested_at: nil} if indexed).to_h}

    if params[:id]
      page = CrawledPage.find(params[:id])
      # Just this field, so an old row that no longer passes validation can
      # still be marked.
      page.set(**changes)
      notice = "Marked #{page} as #{status}."
    else
      ids = selected_ids
      if ids.empty?
        return redirect_back_or_to crawled_pages_path, alert: "Select at least one page to mark as #{status}.", status: :see_other
      end

      count = CrawledPage.where(:_id.in => ids, indexed: !indexed)
        .update_all(changes).modified_count
      notice = count.zero? ? "Those pages were already #{status}." : "Marked #{helpers.pluralize(count, "page")} as #{status}."
    end

    # Back to the list as it was, so working through a filtered list keeps
    # your place.
    redirect_back_or_to crawled_pages_path, notice: notice, status: :see_other
  end

  # Redrawing only the dialog keeps the list behind it exactly as it was
  # while the errors are fixed.
  def render_with_errors(template)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("modal", partial: "dialog", locals: {crawled_page: @crawled_page}),
          status: :unprocessable_content
      end
      format.html { render template, status: :unprocessable_content }
    end
  end

  def set_crawled_page
    @crawled_page = CrawledPage.find(params[:id])
  end

  def crawled_page_params
    params.expect(crawled_page: %i[url last_modified_at indexed])
  end
end
