# encoding: UTF-8

module Google
  module Analytics
    # The blog's own sign that a reader got to the end of an entry, sent only
    # after some time actually reading, so a quick scroll to the footer
    # doesn't count the way GA's 90% scroll does.
    class ArticleReadStat
      include Mongoid::Document
      include DailyStat

      EVENT = "article_read"

      field :page_path, type: String
      field :reads, type: Integer, default: 0
      # Summed over the reads, so the time per read is worked out from it.
      field :read_seconds, type: Integer, default: 0

      key_fields :page_path

      index({date: 1, page_path: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      index({page_path: 1, date: 1})

      validates :page_path, presence: true

      class << self
        def grouped(criteria, by:)
          GroupedScope.new(criteria, keys: by, sums: {reads: "$reads", read_seconds: "$read_seconds"}, row_class: GroupedScope::Row)
        end

        # Days before it have only scrolls to go on.
        def first_date
          order(date: :asc).only(:date).first&.date
        end
      end
    end
  end
end
