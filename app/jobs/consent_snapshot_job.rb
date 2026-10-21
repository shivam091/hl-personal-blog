# encoding: UTF-8

# Re-snapshots the last few days rather than only yesterday, since GA fills a day in late and the
# frontend's last beacons of a day can land after midnight; each run is an upsert, so repeats are harmless.
class ConsentSnapshotJob < ApplicationJob
  queue_as :default

  RECENT_DAYS = 3

  # Returns the days written, for the rake task to report; a day GA hasn't synced is written without
  # GA's figure rather than held up for it.
  def perform(days: RECENT_DAYS, today: Date.current, from: nil, to: nil)
    last = to || today - 1
    first = from || last - (days - 1)
    (first..last).count do |date|
      ConsentSnapshot.record(ConsentStats.inputs_for(date, today: today))
      true
    end.tap { |written| Rails.logger.info("Consent snapshots: #{written} written") }
  end
end
