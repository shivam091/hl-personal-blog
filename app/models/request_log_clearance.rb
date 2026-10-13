# encoding: UTF-8

# Logs share the blog's live database and its storage quota, so the admin
# clears old ones when they choose rather than on a fixed schedule. A form
# object so the date range is validated like any model.
class RequestLogClearance
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :from, :date
  attribute :to, :date
  # So development's noise can be cleared without touching production's logs
  # from the same days.
  attribute :local_only, :boolean, default: false

  validate :dates_must_be_valid
  validate :to_must_not_precede_from

  # Whole days in the app's time zone (IST), the one logs are shown in, so
  # picking one day clears exactly the logs listed under it.
  def scope
    logs = RequestLog.where(created_at: from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day)
    local_only ? logs.local : logs
  end

  # Clearing can take a while on a big range, so it runs after the response
  # instead of keeping the admin waiting.
  def enqueue
    ClearRequestLogsJob.perform_later(from.iso8601, to.iso8601, local_only: local_only)
  end

  private

  # A date that doesn't parse becomes nil, which would otherwise read as
  # "left blank" when it was actually mistyped.
  def dates_must_be_valid
    %i[from to].each do |name|
      next if public_send(name)

      errors.add(name, raw(name).present? ? "is not a valid date" : :blank)
    end
  end

  def to_must_not_precede_from
    errors.add(:to, "can't be before the start date") if from && to && to < from
  end

  def raw(name)
    @attributes[name.to_s].value_before_type_cast
  end
end
