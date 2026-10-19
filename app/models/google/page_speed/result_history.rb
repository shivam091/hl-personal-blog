# encoding: UTF-8

module Google
  module PageSpeed
    # Kept per run because the latest Result is overwritten by the next and a
    # page that got slower after a change would otherwise only ever show its
    # new score.
    class ResultHistory
      include Mongoid::Document
      include Mongoid::Timestamps

      # Lighthouse's scores swing a few points between runs of an unchanged
      # page, so only a bigger drop reads as a regression.
      REGRESSION = 0.1
      FIGURES = %i[
        performance accessibility best_practices seo lab_lcp_ms lab_cls lab_tbt_ms lab_fcp_ms lab_speed_index_ms
        field_lcp_ms field_inp_ms field_cls field_category field_source
      ].freeze

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
      field :field_lcp_ms, type: Float
      field :field_inp_ms, type: Float
      field :field_cls, type: Float
      field :field_category, type: String
      field :field_source, type: String
      field :error, type: String

      index({url: 1, strategy: 1, fetched_at: -1})
      index({fetched_at: -1})

      validates :url, :strategy, :fetched_at, presence: true
      validates :strategy, inclusion: {in: Result::STRATEGIES}

      Regression = Struct.new(:url, :page_path, :strategy, :latest, :previous, keyword_init: true) do
        def drop
          previous.performance - latest.performance
        end
      end

      class << self
        # No figures copied for a failed run so its row doesn't repeat the last
        # good ones as if they'd been measured again.
        def record(result)
          figures = result.error ? {} : FIGURES.index_with { |figure| result[figure] }
          create(url: result.url, page_path: result.page_path, strategy: result.strategy, fetched_at: result.fetched_at,
            error: result.error, **figures)
        end

        def runs(url, strategy)
          where(url: url, strategy: strategy).order(fetched_at: :asc)
        end

        # Only the last two scored runs are compared so a page leaves the list
        # once its latest run is no worse.
        def regressions(scope = all, limit: 10)
          rows = scope.where(:performance.ne => nil).order(fetched_at: :desc).only(:url, :page_path, :strategy, :fetched_at, :performance, :lab_lcp_ms)
            .group_by { |run| [run.url, run.strategy] }
          rows.filter_map do |(url, strategy), runs|
            latest, previous = runs.first(2)
            next unless previous && previous.performance - latest.performance >= REGRESSION - Float::EPSILON

            Regression.new(url: url, page_path: latest.page_path, strategy: strategy, latest: latest, previous: previous)
          end.sort_by { |row| [-row.drop, row.url, row.strategy] }.first(limit)
        end
      end

      # False for a first scored run because there is nothing to have fallen from.
      def regressed_from?(previous)
        !previous.nil? && !performance.nil? && !previous.performance.nil? && previous.performance - performance >= REGRESSION - Float::EPSILON
      end
    end
  end
end
