# encoding: UTF-8

module Mixpanel
  # So a rise on Mixpanel's own charts reads against the post that caused
  # it, as GA's annotations do. Entries already marked are left alone, so a
  # rerun or a backfill adds no duplicates.
  class AnnotationService
    # The same window as GA's, for the same reasons.
    LOOKBACK_DAYS = Google::Analytics::AnnotationService::LOOKBACK_DAYS
    PREFIX = "Published: "

    class << self
      def call(...)
        new(...).call
      end

      def description_for(entry)
        "#{PREFIX}#{entry.name}"
      end
    end

    def initialize(client: Client.new, today: Date.current)
      @client = client
      @today = today
    end

    def call
      result = SyncResult.empty
      return result.tap { result.errors << Client::NOT_CONFIGURED } unless @client.configured?

      from = @today - (LOOKBACK_DAYS - 1)
      listed = @client.app_get("annotations", fromDate: from.iso8601, toDate: @today.iso8601).fetch("results", [])
      marked = listed.to_set { |annotation| [annotation["description"], annotation["date"].to_s[0, 10]] }

      entries(from).each do |entry|
        published = entry.published_at.in_time_zone
        description = self.class.description_for(entry)
        if marked.include?([description, published.to_date.iso8601])
          result.unchanged += 1
          next
        end

        @client.app_post("annotations", date: published.strftime("%Y-%m-%d %H:%M:%S"), description: description, tags: [])
        result.created += 1
      rescue Client::Error => e
        result.errors << "Mixpanel annotation for #{entry.name}: #{e.message}"
      end
      result
    rescue Client::Error => e
      result.errors << "Mixpanel annotations: #{e.message}"
      result
    end

    private

    def entries(from)
      FeedEntry.where(:published_at.gte => from.beginning_of_day).order(published_at: :asc)
    end
  end
end
