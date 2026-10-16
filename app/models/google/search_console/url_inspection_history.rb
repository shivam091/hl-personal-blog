# encoding: UTF-8

module Google
  module SearchConsole
    # A page's UrlInspection is overwritten by each inspection, so when it
    # dropped out of the index, or how long it waited to get in, would be
    # lost. Only changes are kept: every page is re-inspected every few
    # days, and a row per inspection would bury the few that matter under
    # identical ones.
    class UrlInspectionHistory
      include Mongoid::Document

      STATES = %i[verdict coverage_state indexing_state page_fetch_state robots_txt_state].freeze

      # Kept after the page is removed, since its history is still worth
      # reading against the rest.
      belongs_to :crawled_page, optional: true

      field :url, type: String
      field :inspected_at, type: Time
      field :verdict, type: String
      field :coverage_state, type: String
      field :indexing_state, type: String
      field :page_fetch_state, type: String
      field :robots_txt_state, type: String
      field :last_crawled_at, type: Time
      field :google_canonical, type: String

      index({crawled_page_id: 1, inspected_at: -1})

      validates :url, :inspected_at, presence: true

      Drop = Struct.new(:page, :inspection, :indexed_since, :dropped_at, keyword_init: true)

      class << self
        def record(page, inspection)
          last = where(crawled_page_id: page.id).order(inspected_at: :desc).first
          return if last && STATES.all? { |state| last[state] == inspection[state] }

          create(crawled_page: page, url: page.url, inspected_at: inspection.inspected_at, last_crawled_at: inspection.last_crawled_at,
            google_canonical: inspection.google_canonical, **STATES.index_with { |state| inspection[state] })
        end

        def timeline(page)
          where(crawled_page_id: page.id).order(inspected_at: :desc)
        end

        # Pages Google once indexed but no longer does, latest drop first,
        # since one that fell out lately is likeliest to be a change of ours.
        def dropped(limit: 10)
          inspections = UrlInspection.where(:verdict.ne => "PASS").includes(:crawled_page).index_by(&:crawled_page_id)
          where(:crawled_page_id.in => inspections.keys).order(inspected_at: :asc).group_by(&:crawled_page_id).filter_map do |page_id, rows|
            last_indexed = rows.rindex(&:indexed?)
            next unless last_indexed && rows[last_indexed + 1]

            inspection = inspections[page_id]
            Drop.new(page: inspection.crawled_page, inspection: inspection, indexed_since: rows[last_indexed].inspected_at,
              dropped_at: rows[last_indexed + 1].inspected_at)
          end.sort_by { |row| -row.dropped_at.to_f }.first(limit)
        end
      end

      def indexed?
        verdict == "PASS"
      end
    end
  end
end
