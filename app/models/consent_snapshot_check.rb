# encoding: UTF-8

# A night the snapshot job never ran leaves no failed run behind, only a day missing, so that is looked for
# directly. The day before yesterday, since yesterday's is written in the small hours and a check made
# before then would cry wolf.
class ConsentSnapshotCheck
  def initialize(today: Date.current)
    @today = today
  end

  # Nil until snapshots were being stored before that day, so a fresh database isn't read as a broken job.
  def missing_day
    day = @today - 2
    return unless ConsentSnapshot.where(:day.lt => day.iso8601).exists?

    day unless ConsentSnapshot.where(day: day.iso8601).exists?
  end
end
