# encoding: UTF-8

require "csv"

module Google
  module SearchConsole
    class Sitemap
      include Mongoid::Document
      include Mongoid::Timestamps

      field :path, type: String
      field :sitemap_type, type: String
      field :last_submitted_at, type: Time
      field :last_downloaded_at, type: Time
      field :pending, type: Boolean, default: false
      field :sitemaps_index, type: Boolean, default: false
      field :error_count, type: Integer, default: 0
      field :warning_count, type: Integer, default: 0
      field :contents, type: Array, default: []

      index({path: 1}, {unique: true})

      validates :path, presence: true

      def submitted_urls
        contents.sum { |content| content["submitted"].to_i }
      end

      def to_s
        path
      end

      class << self
        def to_csv(sitemaps)
          CSV.generate do |csv|
            csv << ["Path", "Type", "Last submitted", "Last downloaded", "Pending", "Sitemap index", "Errors", "Warnings", "Submitted URLs"]
            sitemaps.each do |sitemap|
              csv << [sitemap.path, sitemap.sitemap_type, sitemap.last_submitted_at&.utc&.iso8601, sitemap.last_downloaded_at&.utc&.iso8601,
                sitemap.pending ? "Yes" : "No", sitemap.sitemaps_index ? "Yes" : "No", sitemap.error_count, sitemap.warning_count,
                sitemap.submitted_urls]
            end
          end
        end
      end
    end
  end
end
