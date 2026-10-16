# encoding: UTF-8

module Google
  module SearchConsole
    # Exists so a crawled page's indexed flag no longer has to be copied over
    # by hand from Google's verdict.
    class UrlInspectionSyncService
      INSPECT_URL = "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect"
      # Google allows 2,000 inspections a day per property; this re-checks a
      # small blog every few days while leaving room for inspecting by hand.
      DEFAULT_LIMIT = 100
      # A refused token or an exhausted quota fails every page alike, so the
      # run stops instead of spending the rest of the batch on the same error.
      MAX_CONSECUTIVE_ERRORS = 3

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(options = {})
        @limit = options.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1..)
        @site = options.fetch(:site) { Rails.application.credentials.dig(:google, :search_console_site) }
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
      end

      def call
        result = SyncResult.empty
        return result unless configured?(result)

        # Locked, so two runs don't spend the day's quota inspecting the same pages.
        synced = SyncLock.hold("google/search_console/url_inspections") do
          consecutive_errors = 0
          pages_due.each do |page|
            inspect_page(page, result)
            consecutive_errors = 0
          rescue ApiClient::Error => e
            result.errors << "URL inspection of #{page.url}: #{e.message}"
            break if (consecutive_errors += 1) >= MAX_CONSECUTIVE_ERRORS
          end
        end
        result.errors << "URL inspection: another sync is already running, so this one was skipped" unless synced
        result
      end

      # Entries just published, and ones still not indexed a few days on, so
      # a new post's verdict is known the day it goes out rather than
      # whenever the daily batch gets to it. Locked like a batch, since it
      # spends the same quota.
      def inspect_new_entries
        result = SyncResult.empty
        return result unless configured?(result)

        synced = SyncLock.hold("google/search_console/url_inspections") do
          consecutive_errors = 0
          NewEntries.new.pages_due.first(@limit).each do |page|
            inspect_page(page, result)
            consecutive_errors = 0
          rescue ApiClient::Error => e
            result.errors << "URL inspection of #{page.url}: #{e.message}"
            break if (consecutive_errors += 1) >= MAX_CONSECUTIVE_ERRORS
          end
        end
        result.errors << "URL inspection: another sync is already running, so this one was skipped" unless synced
        result
      end

      # For a check that can't wait for its turn in the daily batches.
      # Outside the lock, since one inspection can't spend the quota a batch
      # would.
      def inspect_now(page)
        result = SyncResult.empty
        inspect_page(page, result) if configured?(result)
        result
      rescue ApiClient::Error => e
        result.errors << "URL inspection of #{page.url}: #{e.message}"
        result
      end

      private

      def configured?(result)
        result.errors << ApiClient::NOT_CONFIGURED unless @client.configured?
        result.errors << "No Search Console site configured (credentials google.search_console_site)" if @site.blank?
        result.errors.empty?
      end

      # Pages waiting on an indexing request first, so the day it lands is
      # the day it's seen; then new entries Google hasn't indexed yet; then
      # never-inspected and stalest, so the daily batches work through the
      # whole blog in turn.
      def pages_due
        requested = CrawledPage.index_requested.order(index_requested_at: :asc).limit(@limit).to_a
        requested |= NewEntries.new.not_indexed.filter_map(&:page)
        requested = requested.first(@limit)
        # MongoDB reads a limit of 0 as no limit at all.
        return requested if requested.size >= @limit

        uninspected = CrawledPage.not_in(_id: UrlInspection.distinct(:crawled_page_id)).nin(_id: requested.map(&:id))
          .order(url: :asc).limit(@limit - requested.size).to_a
        due = requested + uninspected
        return due if due.size >= @limit

        stale = UrlInspection.nin(crawled_page_id: due.map(&:id)).order(inspected_at: :asc).limit(@limit - due.size)
          .includes(:crawled_page).filter_map(&:crawled_page)
        due + stale
      end

      def inspect_page(page, result)
        inspection_result = @client.post(INSPECT_URL, {inspectionUrl: page.url, siteUrl: @site}).fetch("inspectionResult", {})
        inspection = page.url_inspection || page.build_url_inspection
        crawled_before = inspection.last_crawled_at
        inspection.assign_attributes(attributes_from(inspection_result))
        # Never once the last inspection had a crawl, so a recrawl can't pass
        # for a first one.
        inspection.first_crawled_at ||= inspection.last_crawled_at if crawled_before.nil?
        stamp_first_indexed(page, inspection) if inspection.indexed? && inspection.first_indexed_at.nil?

        outcome = inspection.new_record? ? :created : :updated
        if inspection.save
          UrlInspectionHistory.record(page, inspection)
          result[outcome] += 1
          # Just these fields, so an old row that no longer passes validation
          # is still kept in step. An indexed page's request has landed.
          changes = {}
          changes[:indexed] = inspection.indexed? unless page.indexed == inspection.indexed?
          changes[:index_requested_at] = nil if inspection.indexed? && page.index_requested_at
          page.set(**changes, updated_at: Time.current) if changes.any?
        else
          result.errors << "#{page.url}: #{inspection.errors.full_messages.to_sentence}"
        end
      end

      # From the history when the page was inspected before this was kept, so
      # it isn't dated by the check that happens to fill it in.
      def stamp_first_indexed(page, inspection)
        passes = UrlInspectionHistory.where(crawled_page_id: page.id, verdict: "PASS").order(inspected_at: :asc)
        inspection.first_indexed_at = passes.first&.inspected_at || inspection.inspected_at
        inspection.indexed_after = UrlInspectionHistory.where(crawled_page_id: page.id, :verdict.ne => "PASS", :inspected_at.lt => inspection.first_indexed_at)
          .order(inspected_at: :desc).first&.inspected_at
      end

      def attributes_from(inspection_result)
        index = inspection_result.fetch("indexStatusResult", {})
        rich = inspection_result.fetch("richResultsResult", {})
        {
          inspected_at: Time.current, inspection_link: inspection_result["inspectionResultLink"],
          verdict: index["verdict"], coverage_state: index["coverageState"], robots_txt_state: index["robotsTxtState"],
          indexing_state: index["indexingState"], page_fetch_state: index["pageFetchState"], crawled_as: index["crawledAs"],
          last_crawled_at: (Time.iso8601(index["lastCrawlTime"]) if index["lastCrawlTime"].present?),
          google_canonical: index["googleCanonical"], user_canonical: index["userCanonical"],
          sitemaps: Array(index["sitemap"]), referring_urls: Array(index["referringUrls"]),
          rich_results_verdict: rich["verdict"],
          rich_results: Array(rich["detectedItems"]).map do |detected|
            {
              "type" => detected["richResultType"],
              "items" => Array(detected["items"]).map do |item|
                {"name" => item["name"], "issues" => Array(item["issues"]).map { |issue| {"message" => issue["issueMessage"], "severity" => issue["severity"]} }}
              end
            }
          end
        }
      end
    end
  end
end
