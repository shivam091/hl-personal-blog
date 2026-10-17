# encoding: UTF-8

module Google
  module Analytics
    # Which kind of entry, category and tags each page was viewed as. Only
    # page views carry them, so a reader's engagement and scrolls on a page
    # would all fall under "(not set)" if read by these; they're joined to
    # the page's own traffic by path instead.
    class ContentGroupStat
      include Mongoid::Document
      include DailyStat

      # The blog's content_group values; GA's contentGroup, unlike the other
      # two, needs no registering.
      GROUPS = %w[post tutorial snippet series listing page].freeze
      # The blog's own word for a page with no category.
      NO_CATEGORY = "(none)"

      field :page_path, type: String
      field :content_group, type: String
      field :content_category, type: String
      # Comma-joined slugs, as the blog sends them.
      field :content_tags, type: String
      field :views, type: Integer, default: 0

      key_fields :page_path, :content_group, :content_category, :content_tags

      index({date: 1, page_path: 1, content_group: 1, content_category: 1, content_tags: 1}, {unique: true})

      validates :page_path, :content_group, :content_category, :content_tags, presence: true

      class << self
        def grouped(criteria, by:)
          GroupedScope.new(criteria, keys: by, sums: {views: "$views"}, row_class: GroupedScope::Row)
        end

        # The way each page was viewed most in the period, so a page moved to
        # another category counts once, under where most readers found it.
        def labels(criteria)
          grouped(criteria, by: %i[page_path content_group content_category content_tags]).to_a
            .group_by { |row| row[:page_path] }
            .transform_values { |rows| rows.max_by { |row| [row[:views].to_i, row[:content_group].to_s] } }
        end
      end
    end
  end
end
