# encoding: UTF-8

module Google
  module SearchConsole
    # So every Search Console breakdown is keyed and measured the same way
    # and one breakdown can be read against another row for row.
    module Performance
      extend ActiveSupport::Concern

      # Search Console reports each results surface separately, and their
      # figures overlap nowhere, so a row belongs to exactly one.
      SEARCH_TYPES = %w[web image video news discover googleNews].freeze

      # Position is weighted by impressions, as Search Console averages it, so
      # a day with one impression can't drag a period's average about.
      GROUP_SUMS = {
        clicks: "$clicks",
        impressions: "$impressions",
        weighted_position: {"$multiply" => ["$position", "$impressions"]}
      }.freeze
      GROUP_DERIVED = {
        "ctr" => {"$cond" => [{"$gt" => ["$impressions", 0]}, {"$divide" => ["$clicks", "$impressions"]}, 0]},
        "position" => {"$cond" => [{"$gt" => ["$impressions", 0]}, {"$divide" => ["$weighted_position", "$impressions"]}, nil]}
      }.freeze

      class Total < GroupedScope::Row
        # Read back as a time at midnight UTC, which isn't how a day is shown.
        def date
          self[:date]&.to_date
        end

        def clicks
          self[:clicks].to_i
        end

        def impressions
          self[:impressions].to_i
        end

        def ctr
          self[:ctr].to_f
        end

        def position
          self[:position]&.to_f
        end
      end

      included do
        include DailyStat

        field :search_type, type: String, default: "web"
        # The full URL, because that's how Search Console names pages.
        field :page, type: String
        # Analytics names pages by path, so this is what the two sources join on.
        field :page_path, type: String
        field :clicks, type: Integer, default: 0
        field :impressions, type: Integer, default: 0
        field :ctr, type: Float, default: 0.0
        field :position, type: Float

        # Every read is within a date range, so the range follows the match.
        index({page_path: 1, date: 1})

        validates :search_type, inclusion: {in: SEARCH_TYPES}

        # Search Console counts a result once for the whole site but once per
        # page shown in it when split by page, so the two kinds of total
        # differ and are stored side by side: without a page for the site's.
        scope :site_wide, -> { where(page: nil) }
        scope :per_page, -> { where(:page.ne => nil) }
      end

      class_methods do
        def breakdown(*fields)
          key_fields :search_type, :page, *fields
          index({date: 1, search_type: 1, page: 1, **fields.index_with(1)}, {unique: true})
          fields.each { |field| index({field => 1, date: 1}) }
        end

        def grouped(criteria, by:)
          GroupedScope.new(criteria, keys: by, sums: GROUP_SUMS, derived: GROUP_DERIVED, row_class: Total)
        end
      end
    end
  end
end
