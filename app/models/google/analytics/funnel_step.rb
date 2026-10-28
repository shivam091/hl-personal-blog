# encoding: UTF-8

module Google
  module Analytics
    # Embedded, since a step means nothing outside its funnel and GA needs
    # them in order.
    class FunnelStep
      include Mongoid::Document
      include StripAttribute

      embedded_in :funnel_definition, class_name: "Google::Analytics::FunnelDefinition"

      field :name, type: String
      field :event, type: String
      # One page, matched with whatever query string followed it.
      field :path, type: String
      # Path prefixes, any of which will do, so "an entry" is any of the
      # sections entries live in.
      field :paths, type: Array, default: []
      # Kept to the live site's hostname. Off for events the blog's server
      # sends, which GA files without one.
      field :site, type: Boolean, default: true

      strip_attributes! :name, :event, :path

      validates :name, :event, presence: true
      validates :event, format: {with: /\A[A-Za-z][A-Za-z0-9_]*\z/, message: "must be a GA event name, like page_view", allow_blank: true}
      validates :path, format: {with: %r{\A/}, message: "must start with /", allow_blank: true}
      validate :paths_must_start_with_slash

      # One box for the prefixes, since a funnel rarely needs more than a few.
      def paths_list
        paths.join(", ")
      end

      def paths_list=(value)
        self.paths = value.to_s.split(",").map(&:strip).compact_blank.uniq
      end

      def to_s
        name
      end

      private

      def paths_must_start_with_slash
        errors.add(:paths_list, "must each start with /") if paths.any? { |prefix| !prefix.start_with?("/") }
      end
    end
  end
end
