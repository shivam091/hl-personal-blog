# encoding: UTF-8

module Google
  module SafeBrowsing
    # Whether Google lists a link readers followed out of the blog as
    # malware or phishing, since a site a post links to can turn bad long
    # after the post is written.
    class LinkCheck
      include Mongoid::Document
      include Mongoid::Timestamps

      # Safe Browsing's names, read as a reader would put them.
      THREATS = {
        "MALWARE" => "Malware",
        "SOCIAL_ENGINEERING" => "Phishing or deception",
        "UNWANTED_SOFTWARE" => "Unwanted software",
        "POTENTIALLY_HARMFUL_APPLICATION" => "Harmful app"
      }.freeze

      field :url, type: String
      field :checked_at, type: Time
      field :threat_types, type: Array, default: []
      # When it was first found unsafe, so it's known how long readers have
      # been sent there; cleared once Google drops it.
      field :flagged_at, type: Time

      index({url: 1}, {unique: true})
      index({flagged_at: -1})

      validates :url, presence: true

      scope :flagged, -> { where(:threat_types.ne => []) }

      def flagged?
        threat_types.any?
      end

      def threat_labels
        threat_types.map { |type| THREATS.fetch(type, type.humanize) }
      end

      class << self
        def to_csv(checks)
          CSV.generate do |csv|
            csv << ["URL", "Threats", "Flagged since", "Checked"]
            checks.each do |check|
              csv << [
                check.url,
                check.threat_labels.join(", "),
                check.flagged_at&.utc&.iso8601,
                check.checked_at&.utc&.iso8601
              ]
            end
          end
        end
      end
    end
  end
end
