# encoding: UTF-8

# Re-snapshots the last few days rather than only yesterday, since GA fills a day in late and the
# frontend's last beacons of a day can land after midnight; each run is an upsert, so repeats are harmless.
class ConsentSnapshotJob < ApplicationJob
  queue_as :default

  RECENT_DAYS = 3

  # Returns the days written, for the rake task to report; a day GA hasn't synced is written without
  # GA's figure rather than held up for it. Recorded like a sync, so a failed night shows where theirs do.
  def perform(days: RECENT_DAYS, today: Date.current, from: nil, to: nil, request_id: nil, trigger: "job")
    last = to || today - 1
    first = from || last - (days - 1)
    result = SyncRequest.track("consent_snapshot", request_id: request_id, trigger: trigger, from_date: first, to_date: last) do
      (first..last).each_with_object(SyncResult.empty) do |date, counts|
        existed = ConsentSnapshot.where(day: date.iso8601).exists?
        ConsentSnapshot.record(ConsentStats.inputs_for(date, today: today))
        existed ? counts.updated += 1 : counts.created += 1
      end
    end
    (result.created + result.updated).tap { |written| Rails.logger.info("Consent snapshots: #{written} written") }
  end
end
