# encoding: UTF-8

class Filtering
  # The blog has pages that aren't content, such as the home page and tag
  # listings, so a list of views can be narrowed to what the feed publishes.
  class FeedEntries < Select
    ONLY = "true".freeze

    def initialize(name = :only_feed, label: "Feed entries")
      super(name, field: :slug, label: label, choices: {ONLY => "Feed entries only"}, blank_label: "Every page")
    end

    def apply(scope, values)
      values[name] ? scope.where(:slug.in => slugs) : scope
    end

    private

    # Both with and without a trailing slash, since a slug may be stored either way.
    def slugs
      paths = FeedEntry.pluck(:_id).filter_map { |url| IndexCoverage.path_of(url) }
      (paths + paths.map { |path| path.chomp("/") }).uniq
    end
  end
end
