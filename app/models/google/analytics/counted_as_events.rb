# encoding: UTF-8

module Google
  module Analytics
    # Counted the way events are, so their totals read alike.
    module CountedAsEvents
      def grouped(criteria, by:)
        EventStat.grouped(criteria, by: by)
      end
    end
  end
end
