# encoding: UTF-8

module Google
  # Google's reports can be fetched again for any span of days, so a gap can
  # be backfilled or days Google has since revised redone on demand. A form
  # object so the range is validated like any model.
  class SyncRange
    include ActiveModel::Model
    include ActiveModel::Attributes

    DEFAULT_DAYS = 7

    attribute :from, :date, default: -> { Date.current - (DEFAULT_DAYS - 1) }
    attribute :to, :date, default: -> { Date.current }
    # Google keeps only so much history, and earlier days would come back
    # empty, looking like a sync that silently failed.
    attr_accessor :earliest

    validate :dates_must_be_valid
    validate :to_must_not_precede_from
    validate :to_must_not_be_in_the_future
    validate :from_must_not_precede_earliest

    def days
      (to - from).to_i + 1
    end

    private

    # A date that doesn't parse becomes nil, which would otherwise read as
    # "left blank" when it was actually mistyped.
    def dates_must_be_valid
      %i[from to].each do |name|
        next if public_send(name)

        errors.add(name, @attributes[name.to_s].value_before_type_cast.present? ? "is not a valid date" : :blank)
      end
    end

    def to_must_not_precede_from
      errors.add(:to, "can't be before the start date") if from && to && to < from
    end

    def to_must_not_be_in_the_future
      errors.add(:to, "can't be in the future") if to && to > Date.current
    end

    def from_must_not_precede_earliest
      errors.add(:from, "can't be before #{I18n.l(earliest)}, the oldest day Google keeps") if from && earliest && from < earliest
    end
  end
end
