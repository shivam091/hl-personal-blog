# encoding: UTF-8

module Google
  # Over every reader in the period, whichever breakdown is open, since GA
  # stores new and returning apart from the other breakdowns.
  module VisitorWeeks
    private

    def load_visitor_weeks
      @visitor_weeks = Analytics::Stat.weekly_views(@period)
      # Only when the earlier period was synced, as for the report's own
      # figures, so a first period doesn't read as a jump from nothing.
      return unless @previous_totals

      before = Analytics::Stat.weekly_views(@period.previous)
      @previous_visitor_weeks = before[:weeks].each_index.map { |index| before[:views].values.sum { |views| views[index].to_i } }.first(@visitor_weeks[:weeks].size)
    end
  end
end
