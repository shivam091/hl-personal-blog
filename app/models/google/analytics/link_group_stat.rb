# encoding: UTF-8

module Google
  module Analytics
    # The blog's outbound links that carry a ga-* class (core stack, article
    # links, social profiles), from GA's own outbound click, since the blog
    # no longer sends an event of its own for them and the class is the only
    # thing that says which kind of link it was.
    class LinkGroupStat
      include Mongoid::Document
      include DailyStat

      # As the blog names them, without the "ga-" it adds.
      GROUPS = {"core-stack" => "Core stack", "article-link" => "Link in an entry", "social" => "Social profile"}.freeze
      CLASS_PATTERN = /(?:\A|\s)ga-(#{GROUPS.keys.map { |group| Regexp.escape(group) }.join("|")})(?:\s|\z)/

      field :page_path, type: String
      field :link_url, type: String
      field :link_group, type: String
      field :event_count, type: Integer, default: 0

      key_fields :page_path, :link_url, :link_group

      index({date: 1, page_path: 1, link_url: 1, link_group: 1}, {unique: true})
      index({link_group: 1, date: 1})

      validates :page_path, :link_url, presence: true
      validates :link_group, inclusion: {in: GROUPS.keys}

      extend CountedAsEvents

      class << self
        # GA reports a link's whole class attribute, whose other classes
        # change with every restyle, so rows are summed under the one class
        # that names the group. Clicks only, since users can't be added up
        # across those rows.
        def sync(rows, result = SyncResult.empty, **)
          grouped = rows.filter_map do |row|
            group = row[:link_classes].to_s[CLASS_PATTERN, 1]
            row.except(:link_classes).merge(link_group: group) if group
          end
          summed = grouped.group_by { |row| row.values_at(:date, :page_path, :link_url, :link_group) }.map do |_, same|
            same.first.merge(event_count: same.sum { |row| row[:event_count].to_i })
          end
          super(summed, result, **)
        end
      end
    end
  end
end
