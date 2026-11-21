# encoding: UTF-8

# Request logs and external calls share the blog's live database and its
# storage quota, so they're read once a week and then cleared.
class MonitoringReview
  def initialize(until_time: Time.zone.now)
    @until_time = until_time
  end

  def since
    @since ||= (@until_time - 7.days).beginning_of_day
  end

  def until_time
    @until_time
  end

  def requests
    RequestLog.where(created_at: since..@until_time)
  end

  def server_errors
    requests.where(:status.gte => 500)
  end

  def external_calls
    ExternalCall.where(created_at: since..@until_time)
  end

  def failed_external_calls
    external_calls.any_of({status: nil}, {:status.gte => 400})
  end

  def clean?
    server_errors.none? && failed_external_calls.none?
  end

  class << self
    # Before today, so the whole of Sunday goes and nothing from Monday is lost
    # when GitHub starts the run late.
    def clear_before
      Time.zone.today.beginning_of_day
    end

    def clear
      {
        request_logs: RequestLog.where(:created_at.lt => clear_before).delete_all,
        external_calls: ExternalCall.where(:created_at.lt => clear_before).delete_all
      }
    end
  end
end
