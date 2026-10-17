# encoding: UTF-8

module Google
  module Analytics
    # Kept because a session's source credits only the latest visit and
    # hides what first brought new readers in.
    class UserAcquisitionStat
      include Mongoid::Document
      include Traffic

      USER_COUNTS = %i[total_users returning_users].freeze

      class Total < Traffic::Total
        USER_COUNTS.each do |count|
          define_method(count) { self[count].to_i }
        end
      end

      field :first_channel_group, type: String
      field :first_source, type: String
      field :first_medium, type: String
      field :total_users, type: Integer, default: 0
      field :returning_users, type: Integer, default: 0

      breakdown :first_channel_group, :first_source, :first_medium

      class << self
        def grouped(criteria, by:)
          GroupedScope.new(criteria, keys: by, sums: Traffic::GROUP_SUMS.merge(USER_COUNTS.index_with { |count| "$#{count}" }),
            derived: Traffic::GROUP_DERIVED, row_class: Total)
        end
      end
    end
  end
end
