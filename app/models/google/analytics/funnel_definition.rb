# encoding: UTF-8

module Google
  module Analytics
    # Stored rather than written into the code, so a funnel for a new
    # conversion can be added without a deploy. Admin-owned, so it keeps
    # its own indexes.
    class FunnelDefinition
      include Mongoid::Document
      include Mongoid::Timestamps
      include StripAttribute

      # Where the blog's entries live, so a step on an entry isn't any page.
      ENTRY_PREFIXES = FeedEntry::TYPES.map { |type| "/#{type}/" }.freeze
      # GA's funnel report takes no more steps than this.
      MAX_STEPS = 10

      # The funnels the blog had before they could be edited, so a fresh
      # database starts with them rather than with nothing. Subscribing and
      # getting in touch are sent from the blog's server, which GA files
      # without a hostname, so only the steps before them are kept to the
      # live site. A reader can download the resume from the footer of any
      # page, so no page stands between visiting and it.
      DEFAULTS = [
        {
          key: "newsletter",
          title: "Reading to subscribing",
          steps: [
            {name: "Visited the blog", event: "session_start"},
            {name: "Read an entry", event: "page_view", paths: ENTRY_PREFIXES},
            {name: "Subscribed to the newsletter", event: "newsletter_subscribe", site: false}
          ]
        },
        {
          key: "contact",
          title: "Visiting to getting in touch",
          steps: [
            {name: "Visited the blog", event: "session_start"},
            {name: "Opened the contact page", event: "page_view", path: "/contact"},
            {name: "Sent a message", event: "contact_submit", site: false}
          ]
        },
        {
          key: "share",
          title: "Reading to sharing",
          # The share bar sent nothing to GA before this.
          counted_since: Date.new(2026, 10, 23),
          steps: [
            {name: "Visited the blog", event: "session_start"},
            {name: "Read an entry", event: "page_view", paths: ENTRY_PREFIXES},
            {name: "Shared the entry", event: "share", paths: ENTRY_PREFIXES}
          ]
        },
        {
          key: "resume",
          title: "Visiting to downloading the resume",
          # The resume link sent nothing to GA before this.
          counted_since: TrackedSince::RESUME_DOWNLOADS,
          steps: [
            {name: "Visited the blog", event: "session_start"},
            {name: "Downloaded the resume", event: "download_resume"}
          ]
        }
      ].freeze

      field :key, type: String
      field :title, type: String
      field :position, type: Integer, default: 0
      # The day the last step began to be tracked, so earlier days aren't
      # read as readers who chose not to take it.
      field :counted_since, type: Date

      embeds_many :steps, class_name: "Google::Analytics::FunnelStep", cascade_callbacks: true
      # Only a new step left blank is dropped; a saved one is removed by
      # ticking it, so clearing its fields by mistake can't lose it.
      accepts_nested_attributes_for :steps, allow_destroy: true, reject_if: lambda { |attributes|
        attributes = attributes.with_indifferent_access
        attributes[:id].blank? && attributes.values_at(:name, :event, :path, :paths_list).all?(&:blank?)
      }

      index({key: 1}, {unique: true})
      index({position: 1, title: 1})

      strip_attributes! :key, :title

      validates :key, presence: true, uniqueness: true, format: {with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/, message: "must be lowercase words joined by hyphens", allow_blank: true}
      validates :title, presence: true
      validate :steps_must_fit_a_funnel

      scope :ordered, -> { order(position: :asc, title: :asc) }

      class << self
        # Seeded on first read rather than by a script, so the live
        # database is only ever written by someone using the admin.
        def all_or_defaults
          seed_defaults unless exists?
          ordered.to_a
        end

        def seed_defaults
          DEFAULTS.each_with_index do |attributes, position|
            create(**attributes, position: position)
          rescue Mongo::Error::OperationFailure => e
            # Another request seeded it first.
            raise unless e.code == 11000
          end
        end
      end

      # Its conversion is sent from the blog's server, so a reader whose
      # browser blocks Analytics converts without the earlier steps.
      def server_sent?
        steps.last&.site == false
      end

      # Every step and the funnel itself, so a cached report is asked again
      # once anything in it changes.
      def cache_version
        Digest::MD5.hexdigest(as_document.to_json)
      end

      def to_s
        title
      end

      private

      def steps_must_fit_a_funnel
        kept = steps.reject(&:marked_for_destruction?)
        errors.add(:steps, "need at least two, or there's nothing to drop out between") if kept.size < 2
        errors.add(:steps, "can't be more than #{MAX_STEPS}, GA's limit") if kept.size > MAX_STEPS
      end
    end
  end
end
