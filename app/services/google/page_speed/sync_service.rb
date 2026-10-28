# encoding: UTF-8

module Google
  module PageSpeed
    # A few at a time, oldest result first, since each PageSpeed run loads
    # the page in a real browser and takes a while.
    class SyncService
      RUN_URL = "https://www.googleapis.com/pagespeedonline/v5/runPagespeed"
      # Enough that every entry is retested every few days by a daily run,
      # without the run taking most of an hour.
      DEFAULT_LIMIT = 30
      # A refused key or an exhausted quota fails every page alike, so the
      # run stops instead of spending the rest of the batch on the same error.
      MAX_CONSECUTIVE_ERRORS = 3
      CATEGORIES = {
        performance: "performance",
        accessibility: "accessibility",
        best_practices: "best-practices",
        seo: "seo"
      }.freeze
      LAB_AUDITS = {
        lab_lcp_ms: "largest-contentful-paint",
        lab_cls: "cumulative-layout-shift",
        lab_tbt_ms: "total-blocking-time",
        lab_fcp_ms: "first-contentful-paint",
        lab_speed_index_ms: "speed-index"
      }.freeze
      FIELD_METRICS = {
        field_lcp_ms: "LARGEST_CONTENTFUL_PAINT_MS",
        field_inp_ms: "INTERACTION_TO_NEXT_PAINT",
        field_cls: "CUMULATIVE_LAYOUT_SHIFT_SCORE"
      }.freeze

      class << self
        def call(...)
          new(...).call
        end
      end

      # Unknown keys raise, so a misspelt option fails loudly instead of
      # quietly falling back to its default.
      def initialize(options = {})
        options.assert_valid_keys(:limit, :client, :home)
        @limit = options.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1..)
        @client = options.fetch(:client) { KeyClient.new }
        @home = options.fetch(:home) { "https://#{Analytics::SyncService::HOSTNAME}/" }
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << KeyClient::NOT_CONFIGURED } unless @client.configured?

        # Locked, so two runs don't spend the quota testing the same pages.
        synced = SyncLock.hold("google/page_speed") do
          consecutive_errors = 0
          urls_due.each do |url|
            Result::STRATEGIES.each { |strategy| test(url, strategy, result) }
            consecutive_errors = 0
          rescue KeyClient::Error => e
            result.errors << "PageSpeed of #{url}: #{e.message}"
            break if (consecutive_errors += 1) >= MAX_CONSECUTIVE_ERRORS
          end
        end
        unless synced
          result.errors << "PageSpeed: another sync is already running, so this one was skipped"
        end
        result
      end

      private

      # Never-tested first, then the stalest, so daily runs work through the
      # whole blog in turn. Crawled pages too, since listings, tags and the
      # static pages are in no feed but are just as often landed on.
      def urls_due
        urls = candidate_urls
        tested = Result.where(:url.in => urls)
                  .group_by(&:url)
                  .transform_values { |results| results.map(&:fetched_at).compact.min }
        urls.sort_by { |url| [tested[url] ? 1 : 0, tested[url] || Time.at(0), url] }.first(@limit)
      end

      # Only the blog's own pages, since a crawl report can list other hosts,
      # and not its sitemaps or files, which Lighthouse can't score. One URL
      # per page with or without its trailing slash, the first spelling
      # kept, so a page isn't tested twice a turn.
      def candidate_urls
        host = URI.parse(@home).host
        crawled = CrawledPage.pluck(:url).select do |url|
          uri = URI.parse(url)
          uri.host == host && !File.extname(uri.path).match?(/\A\.(xml|txt|pdf|png|jpe?g|gif|svg|webp|ico|json|rss)\z/i)
        rescue URI::InvalidURIError
          false
        end
        [@home, *FeedEntry.pluck(:_id), *crawled].map { |url| url.split("#").first }.uniq do |url|
          url.end_with?("/") && URI.parse(url).path != "/" ? url.chomp("/") : url
        rescue URI::InvalidURIError
          url
        end
      end

      # A failed run keeps the last good figures but is dated, so a page that
      # always fails takes its turn like the rest instead of being first in
      # line every day.
      def test(url, strategy, result)
        record = Result.find_or_initialize_by(url: url, strategy: strategy)
        response = @client.get(RUN_URL,
          url: url,
          strategy: strategy,
          category: CATEGORIES.values.map { |category| category.upcase.tr("-", "_") }
        )
        record.assign_attributes(attributes_from(response).merge(
          page_path: IndexCoverage.path_of(url),
          fetched_at: Time.current,
          error: nil
        ))
        save(record, result)
      rescue KeyClient::Error => e
        record.assign_attributes(page_path: IndexCoverage.path_of(url), fetched_at: Time.current, error: e.message)
        ResultHistory.record(record) if record.save
        raise
      end

      def save(record, result)
        outcome = record.new_record? ? :created : :updated
        if record.save
          ResultHistory.record(record)
          result[outcome] += 1
        else
          result.errors << "#{record.url}: #{record.errors.full_messages.to_sentence}"
        end
      end

      # CLS is given as a hundredfold integer in the field figures ("5" is
      # 0.05). A page with too few Chrome users has none of its own, so the
      # site's are taken instead and marked as such.
      def attributes_from(response)
        lighthouse = response.fetch("lighthouseResult", {})
        page = response.fetch("loadingExperience", {})
        if page["metrics"].present? && !page["origin_fallback"]
          experience = page
          source = "page"
        else
          experience = response.fetch("originLoadingExperience", {})
          source = "origin"
        end
        field = FIELD_METRICS.to_h do |attribute, metric|
          value = experience.dig("metrics", metric, "percentile")
          [attribute, value && (attribute == :field_cls ? value / 100.0 : value.to_f)]
        end
        {
          **CATEGORIES.to_h { |attribute, category| [attribute, lighthouse.dig("categories", category, "score")] },
          **LAB_AUDITS.to_h { |attribute, audit| [attribute, lighthouse.dig("audits", audit, "numericValue")] },
          **field,
          field_category: experience["overall_category"],
          field_source: (source if experience["metrics"].present?)
        }
      end
    end
  end
end
