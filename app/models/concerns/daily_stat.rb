# encoding: UTF-8

require "csv"

# Reports are re-fetched for recent days because their figures keep
# settling for a few days, so syncing updates rows in place instead of
# adding duplicates.
module DailyStat
  extend ActiveSupport::Concern

  included do
    include Mongoid::Timestamps

    field :date, type: Date
    validates :date, presence: true
  end

  class_methods do
    # Per model, since what makes a row unique differs from report to report.
    def key_fields(*fields)
      @key_fields = [:date, *fields]
    end

    # Loaded a day at a time, so a backfill of months doesn't hold every
    # stored row in memory at once. Scoped when a model holds several reports'
    # rows, so one report's row is never matched against another's.
    def sync(rows, result = SyncResult.empty, scope: all)
      rows.group_by { |row| row[:date] }.each do |date, day_rows|
        existing = scope.where(date: date).index_by { |stat| key_of(stat) }
        day_rows.each { |row| sync_row(existing[key_of(row)] || new, row, result) }
      end
      result
    end

    def to_csv(stats)
      columns = fields.keys - %w[_id created_at updated_at]
      CSV.generate do |csv|
        csv << columns.map { |name| human_attribute_name(name) }
        stats.each { |stat| csv << columns.map { |name| csv_value(stat[name]) } }
      end
    end

    private

    def csv_value(value)
      case value
      when Date then value.iso8601
      when Hash, Array then value.to_json
      else value
      end
    end

    def key_of(record)
      @key_fields.map { |field| record[field] }
    end

    def sync_row(stat, row, result)
      stat.assign_attributes(row)
      return result.unchanged += 1 unless stat.new_record? || stat.changed?

      outcome = stat.new_record? ? :created : :updated
      if stat.save
        result[outcome] += 1
      else
        result.errors << "#{key_of(stat).compact.join(" ")}: #{stat.errors.full_messages.to_sentence}"
      end
    end
  end
end
