# encoding: UTF-8

module Google
  module SafeBrowsing
    # Checks every link readers have clicked out to against Google's lists
    # on each run: one request covers hundreds of links, and a site can be
    # listed at any time. The Lookup API is for non-commercial use, which a
    # personal blog's admin is.
    class SyncService
      FIND_URL = "https://safebrowsing.googleapis.com/v4/threatMatches:find"
      # The most URLs Google takes in one request.
      BATCH_SIZE = 500

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(client: KeyClient.new)
        @client = client
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << KeyClient::NOT_CONFIGURED } unless @client.configured?

        synced = SyncLock.hold("google/safe_browsing") do
          links.each_slice(BATCH_SIZE) { |batch| record(batch, threats(batch), result) }
        rescue KeyClient::Error => e
          result.errors << "Safe Browsing: #{e.message}"
        end
        result.errors << "Safe Browsing: another sync is already running, so this one was skipped" unless synced
        result
      end

      private

      # Only real links: GA marks a click it couldn't tie to one as "(not set)".
      def links
        Analytics::OutboundLinkStat.distinct(:link_url).select { |url| url.to_s.match?(%r{\Ahttps?://}i) }.sort
      end

      def threats(batch)
        response = @client.post(FIND_URL, {
          client: {clientId: "harshal-ladhe-backend", clientVersion: "1.0"},
          threatInfo: {
            threatTypes: LinkCheck::THREATS.keys, platformTypes: ["ANY_PLATFORM"], threatEntryTypes: ["URL"],
            threatEntries: batch.map { |url| {url: url} }
          }
        })
        Array(response["matches"]).each_with_object(Hash.new { |hash, url| hash[url] = [] }) do |match, found|
          found[match.dig("threat", "url")] |= [match["threatType"]]
        end
      end

      def record(batch, found, result)
        now = Time.current
        existing = LinkCheck.where(:url.in => batch).index_by(&:url)
        batch.each do |url|
          check = existing[url] || LinkCheck.new(url: url)
          types = found.fetch(url, []).sort
          was_flagged = check.flagged?
          check.assign_attributes(
            threat_types: types,
            flagged_at: (types.any? ? (was_flagged ? check.flagged_at : now) : nil)
          )

          outcome = if check.new_record? then :created
          elsif check.changed? then :updated
          else :unchanged
          end

          check.checked_at = now

          if check.save
            result[outcome] += 1
          else
            result.errors << "#{url}: #{check.errors.full_messages.to_sentence}"
          end
        end
      end
    end
  end
end
