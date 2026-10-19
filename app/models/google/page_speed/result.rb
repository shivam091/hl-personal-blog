# encoding: UTF-8

module Google
  module PageSpeed
    # The latest PageSpeed Insights run per page and device, so a slow post
    # is spotted without running Lighthouse by hand. Only the latest is kept
    # here, so the list stays one row per page; every run is in ResultHistory.
    class Result
      include Mongoid::Document
      include Mongoid::Timestamps

      STRATEGIES = %w[mobile desktop].freeze
      CATEGORIES = %w[performance accessibility best_practices seo].freeze
      # Google's own Core Web Vitals thresholds: good up to the first value,
      # poor beyond the second.
      THRESHOLDS = {lcp_ms: [2500, 4000], inp_ms: [200, 500], cls: [0.1, 0.25]}.freeze

      field :url, type: String
      field :page_path, type: String
      field :strategy, type: String
      field :fetched_at, type: Time
      field :performance, type: Float
      field :accessibility, type: Float
      field :best_practices, type: Float
      field :seo, type: Float
      field :lab_lcp_ms, type: Float
      field :lab_cls, type: Float
      field :lab_tbt_ms, type: Float
      field :lab_fcp_ms, type: Float
      field :lab_speed_index_ms, type: Float
      # Real Chrome users' 75th percentiles over the last 28 days, from CrUX.
      # Empty when too few Chrome users visited for Google to say.
      field :field_lcp_ms, type: Float
      field :field_inp_ms, type: Float
      field :field_cls, type: Float
      field :field_category, type: String
      # "page", or "origin" when the page had too few Chrome users and Google
      # gave the whole site's figures instead.
      field :field_source, type: String
      field :error, type: String

      index({url: 1, strategy: 1}, {unique: true})
      index({fetched_at: 1})

      validates :url, :strategy, presence: true
      validates :strategy, inclusion: {in: STRATEGIES}

      # Pages tested on both devices, so the gap is between two real scores.
      DeviceGap = Struct.new(:url, :page_path, :mobile, :desktop, keyword_init: true) do
        def gap
          (desktop - mobile).abs
        end
      end

      class << self
        def rating(metric, value)
          return if value.nil?

          good, poor = THRESHOLDS.fetch(metric)
          if value <= good then :good
          elsif value <= poor then :needs_improvement
          else :poor
          end
        end

        # The widest first, since a page much slower on a phone is the one a
        # mobile-only fix would help.
        def device_gaps(scope, limit: 15)
          scope.where(:performance.ne => nil).only(:url, :page_path, :strategy, :performance).group_by(&:url).filter_map do |url, results|
            by_strategy = results.index_by(&:strategy)
            next unless by_strategy.key?("mobile") && by_strategy.key?("desktop")

            DeviceGap.new(
              url: url,
              page_path: results.first.page_path,
              mobile: by_strategy["mobile"].performance * 100,
              desktop: by_strategy["desktop"].performance * 100
            )
          end.sort_by { |row| [-row.gap, row.url] }.first(limit)
        end

        # Each category's average on each device, out of 100, so whether the
        # site as a whole is weak on, say, accessibility shows at once.
        def category_averages(scope)
          results = scope.only(:strategy, *CATEGORIES).to_a
          CATEGORIES.index_with do |category|
            STRATEGIES.index_with do |strategy|
              scores = results.select { |result| result.strategy == strategy }.filter_map { |result| result.public_send(category) }
              (scores.sum / scores.size * 100) if scores.any?
            end
          end
        end

        # Lowest average across the four categories first, so the page
        # weakest overall heads the list rather than one weak on one count.
        def weakest(scope, strategy: "mobile", limit: 10)
          scope.where(strategy: strategy, :performance.ne => nil).only(:url, :page_path, :strategy, *CATEGORIES).to_a
            .sort_by { |result| [CATEGORIES.filter_map { |category| result.public_send(category) }.then { |scores| scores.sum / scores.size }, result.url] }
            .first(limit)
        end

        # Only a page's own field figure, since the site's stands in for every
        # page short of Chrome users and would put them all at one height.
        def lcp_pairs(scope)
          scope.where(field_source: "page", :lab_lcp_ms.ne => nil, :field_lcp_ms.ne => nil)
            .only(:url, :page_path, :strategy, :lab_lcp_ms, :field_lcp_ms).order(url: :asc, strategy: :asc).to_a
        end

        def to_csv(results)
          CSV.generate do |csv|
            csv << [
              "URL", "Device", "Tested", "Performance", "Accessibility", "Best practices", "SEO",
              "Lab LCP (ms)", "Lab CLS", "Lab TBT (ms)", "Lab FCP (ms)", "Lab Speed Index (ms)",
              "Field LCP (ms)", "Field INP (ms)", "Field CLS", "Field category", "Field from", "Error"
            ]
            results.each do |result|
              csv << [
                result.url,
                result.strategy,
                result.fetched_at&.utc&.iso8601,
                *CATEGORIES.map { |category| result[category]&.round(2) },
                result.lab_lcp_ms&.round,
                result.lab_cls&.round(3),
                result.lab_tbt_ms&.round,
                result.lab_fcp_ms&.round,
                result.lab_speed_index_ms&.round,
                result.field_lcp_ms&.round,
                result.field_inp_ms&.round,
                result.field_cls&.round(3),
                result.field_category,
                result.field_source, result.error
              ]
            end
          end
        end
      end
    end
  end
end
