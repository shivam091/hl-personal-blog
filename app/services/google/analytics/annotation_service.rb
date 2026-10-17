# encoding: UTF-8

module Google
  module Analytics
    # So a rise in traffic on GA's own charts reads against the post that
    # caused it. Entries already marked are left alone, so a rerun or a
    # backfill adds no duplicates. Annotating is a write, so it needs the
    # analytics.edit scope.
    class AnnotationService
      # Annotations are only in the alpha API.
      LIST_URL = "https://analyticsadmin.googleapis.com/v1alpha/properties/%{property}/reportingDataAnnotations"
      # Far enough back to cover a feed sync that failed for a while, but not
      # so far that the whole archive is marked at once.
      LOOKBACK_DAYS = 30
      # GA caps a title's length; cut here so the cut title is what's compared.
      TITLE_LIMIT = 50
      DESCRIPTION_LIMIT = 150
      COLOR = "BLUE"

      Annotation = Struct.new(:title, :description, :date, :color, :system_generated, keyword_init: true)

      class << self
        def call(...)
          new(...).call
        end

        def title_for(entry)
          "Published: #{entry.name}".truncate(TITLE_LIMIT)
        end

        def date_from(value)
          Date.new(value["year"], value["month"], value["day"]) if value
        end

        # GA returns annotations a page at a time.
        def list(client, url)
          items = []
          token = nil
          loop do
            page = client.get("#{url}?#{URI.encode_www_form({pageSize: 200, pageToken: token}.compact)}")
            items.concat(Array(page["reportingDataAnnotations"]))
            token = page["nextPageToken"].presence
            break unless token
          end
          items.map do |item|
            Annotation.new(
              title: item["title"], description: item["description"], color: item["color"], system_generated: item["systemGenerated"],
              date: date_from(item["annotationDate"] || item.dig("annotationDateRange", "startDate"))
            )
          end
        end
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: CustomDimensionService::SCOPE) }
        @today = options.fetch(:today) { Date.current }
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        return result.tap { result.errors << "No Analytics property configured (credentials google.analytics_property_id)" } if @property.blank?

        url = format(LIST_URL, property: ERB::Util.url_encode(@property))
        marked = self.class.list(@client, url).to_set { |annotation| [annotation.title, annotation.date] }
        entries.each do |entry|
          date = entry.published_at.in_time_zone.to_date
          title = self.class.title_for(entry)
          if marked.include?([title, date])
            result.unchanged += 1
            next
          end

          @client.post(url, {
            title: title, description: entry.url.to_s.truncate(DESCRIPTION_LIMIT), color: COLOR,
            annotationDate: {year: date.year, month: date.month, day: date.day}
          })
          result.created += 1
        rescue ApiClient::Error => e
          result.errors << "Annotation for #{entry.name}: #{e.message}"
        end
        result
      rescue ApiClient::Error => e
        result.errors << "Analytics annotations: #{e.message}"
        result
      end

      private

      def entries
        FeedEntry.where(:published_at.gte => (@today - (LOOKBACK_DAYS - 1)).beginning_of_day).order(published_at: :asc)
      end
    end
  end
end
