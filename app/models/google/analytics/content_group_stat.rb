# encoding: UTF-8

module Google
  module Analytics
    # Which kind of entry, category and tags each page was viewed as. Only
    # page views carry them, so a reader's engagement and scrolls on a page
    # would all fall under "(not set)" if read by these; they're joined to
    # the page's own traffic by path instead.
    #
    # One row per page and set of labels, with the first and last day it was
    # seen, rather than one a day: the blog works the labels out from the
    # path, so they only change when an entry is moved or retagged, and a
    # daily copy of them would repeat the page traffic's rows.
    class ContentGroupStat
      include Mongoid::Document

      # The blog's content_group values; GA's contentGroup, unlike the other
      # two, needs no registering.
      GROUPS = %w[post tutorial snippet series listing page].freeze
      NO_CATEGORY = "(none)"
      KEY_FIELDS = %i[page_path content_group content_category content_tags].freeze

      field :page_path, type: String
      field :content_group, type: String
      field :content_category, type: String
      field :content_tags, type: String
      field :first_date, type: Date
      field :last_date, type: Date

      index({page_path: 1, content_group: 1, content_category: 1, content_tags: 1}, {unique: true})
      # Every read is of the labels seen within a period.
      index({last_date: 1, first_date: 1})

      validates :page_path, :content_group, :content_category, :content_tags, :first_date, :last_date, presence: true

      class << self
        # Widens each set of labels' days rather than adding up, so the days
        # the sync fetches again leave it as it was.
        def sync(rows, result = SyncResult.empty, **)
          rows.group_by { |row| row.values_at(*KEY_FIELDS) }.each do |key, seen|
            stat = find_or_initialize_by(KEY_FIELDS.zip(key).to_h)
            dates = seen.map { |row| row[:date] }
            stat.first_date = [stat.first_date, *dates].compact.min
            stat.last_date = [stat.last_date, *dates].compact.max
            next result.unchanged += 1 unless stat.new_record? || stat.changed?

            outcome = stat.new_record? ? :created : :updated
            if stat.save
              result[outcome] += 1
            else
              result.errors << "#{key.join(" ")}: #{stat.errors.full_messages.to_sentence}"
            end
          end
          result
        end

        def within(period)
          where(:first_date.lte => period.to, :last_date.gte => period.from)
        end

        def seen_within?(period)
          within(period).exists?
        end

        # The labels each page was last seen with in the period, so a page
        # moved to another category counts once, under where it is now.
        def labels(period)
          within(period).to_a.group_by(&:page_path)
            .transform_values { |stats| stats.max_by { |stat| [[stat.last_date, period.to].min, stat.content_group.to_s] } }
        end
      end
    end
  end
end
