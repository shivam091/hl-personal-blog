# encoding: UTF-8

module Google
  module SearchConsole
    # Kept so a scheduled sync can skip the days Search Console has called
    # final, rather than fetch a fixed window whose older days can no longer
    # change.
    class FinalDate
      include Mongoid::Document

      field :first_incomplete_date, type: Date

      class << self
        def first_incomplete_date
          first&.first_incomplete_date
        end

        def record(date)
          (first || new).update!(first_incomplete_date: date)
        end
      end
    end
  end
end
