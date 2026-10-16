# encoding: UTF-8

# The frontend keeps a page's all-time count as a field but a span's only
# as days inside the document, so lists count all time in the database and
# a span here.
module ListPeriodCounts
  extend ActiveSupport::Concern

  private

  def load_list_period
    @period = ListPeriod.new(params)
  end

  # Sorted here, since the database can't sort on a sum of a document's
  # days; the tiebreaker stays ascending, as Sorting keeps it.
  def sorted_within(scope, counted:)
    key = lambda do |record|
      value = @sorting.column == counted ? yield(record) : record.public_send(@sorting.column)
      [value.nil? ? 0 : 1, value]
    end
    rows = scope.to_a.sort do |a, b|
      order = key.(a) <=> key.(b)
      order = -order if @sorting.direction == "desc"
      order.nonzero? || a.id <=> b.id
    end
    Google::DailyReport::LoadedRows.new(rows)
  end

  def export_filename(name)
    "#{name}-#{@period.all_time? ? Date.current.iso8601 : "#{@period.from.iso8601}-to-#{@period.to.iso8601}"}.csv"
  end
end
