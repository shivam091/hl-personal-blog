# encoding: UTF-8

module Mixpanel
  # Asked of Mixpanel's own retention report rather than worked out here,
  # since that needs every reader's visits across weeks, which the daily
  # figures deliberately don't keep.
  class RetentionCohort
    include Mongoid::Document
    include Mongoid::Timestamps

    # The week readers first came, and how many of them came back in each
    # week after (counts[0] is the first week itself).
    field :cohort_date, type: Date
    field :first, type: Integer, default: 0
    field :counts, type: Array, default: []

    index({cohort_date: 1}, {unique: true})

    validates :cohort_date, presence: true

    def retention(week)
      count = counts[week]
      count.fdiv(first) if count && first.positive?
    end
  end
end
