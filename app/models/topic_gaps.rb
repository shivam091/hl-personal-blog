# encoding: UTF-8

require "csv"

# What readers look for that the blog has no entry on: searches Google shows
# the blog for without an entry answering them, and what readers type into
# the blog's own search and find nothing for. Grouped by the word they
# share, so a topic searched many ways reads as one gap rather than many.
class TopicGaps
  MIN_IMPRESSIONS = {"10" => "10+", "50" => "50+", "100" => "100+", "500" => "500+"}.freeze
  DEFAULT_MIN_IMPRESSIONS = 10
  # An entry naming under half of a query's words is about something else.
  MIN_COVERAGE = 0.5
  # Words that say how someone searches rather than what for.
  STOP_WORDS = %w[
    a an and are as at be by can do does for from how i in is it my of on or the to use using vs what when where which why
    with you your example examples tutorial guide
  ].to_set.freeze
  EXPORTS = {"queries" => "Search queries", "site-search" => "Site search"}.freeze

  Gap = Struct.new(:query, :clicks, :impressions, :position, :page_path, :closest, :reason, keyword_init: true)
  Topic = Struct.new(:word, :gaps, keyword_init: true) do
    def impressions
      gaps.sum(&:impressions)
    end
  end

  attr_reader :period, :country, :min_impressions

  def initialize(period, country: nil, min_impressions: DEFAULT_MIN_IMPRESSIONS)
    @period = period
    @country = country
    @min_impressions = min_impressions
  end

  def any?
    Google::SearchConsole::Stat.exists?
  end

  # Most seen first. Searches for the blog by name are left out, since they
  # find it whatever it has written.
  def gaps
    @gaps ||= begin
      rows = queries.select { |row| row.impressions >= min_impressions && !row[:query].to_s.match?(Google::SearchConsole::QueryGroups::BRAND) }
      ranking = ranking_pages(rows.map { |row| row[:query] })
      rows.filter_map do |row|
        words = words_of(row[:query])
        next if words.empty?

        closest = entries.max_by { |entry| [coverage(words, entry[:words]), -entry[:path].size] }
        closest = nil unless closest && coverage(words, closest[:words]) >= MIN_COVERAGE
        reason = reason(words, ranking[row[:query]], closest)
        next unless reason

        Gap.new(query: row[:query], clicks: row.clicks, impressions: row.impressions, position: row.position,
          page_path: ranking[row[:query]], closest: closest&.fetch(:entry), reason: reason)
      end.sort_by { |gap| [-gap.impressions, gap.query] }
    end
  end

  # Each gap under the word it shares with the most other gaps' impressions,
  # so a topic's queries gather under its own name rather than whichever
  # word comes first; on a tie the earlier word, as a query usually opens
  # with its subject.
  def topics(limit: 20)
    weight = gaps.each_with_object(Hash.new(0)) { |gap, sums| words_of(gap.query).each { |word| sums[word] += gap.impressions } }
    grouped = gaps.group_by { |gap| words_of(gap.query).each_with_index.max_by { |word, index| [weight[word], -index] }.first }
    grouped.map { |word, of_word| Topic.new(word: word, gaps: of_word) }
      .sort_by { |topic| [-topic.impressions, topic.word] }.first(limit || grouped.size)
  end

  def site_search
    @site_search ||= Google::Analytics::SiteSearch.new(period)
  end

  def not_found_terms(limit: 20)
    site_search.not_found_terms(limit: limit)
  end

  def to_csv(export = EXPORTS.keys.first)
    CSV.generate do |csv|
      if export == "site-search"
        csv << ["Search term", "Searches finding nothing", "Searches"]
        not_found_terms(limit: nil).each { |term| csv << [term.term, term.not_found, term.searches] }
      else
        csv << ["Topic", "Query", "Clicks", "Impressions", "Position", "Ranking page", "Closest entry", "Why"]
        topics(limit: nil).each do |topic|
          topic.gaps.each do |gap|
            csv << [topic.word, gap.query, gap.clicks, gap.impressions, gap.position&.round(1), gap.page_path, gap.closest&.url, gap.reason]
          end
        end
      end
    end
  end

  private

  # A country's from the report asked of Search Console by query and
  # country, which counts every page together, as the site-wide one does.
  def queries
    if country
      stat = Google::SearchConsole::QueryCountryStat
      stat.grouped(period.apply(stat.site_wide.where(country: country)), by: [:query]).to_a
    else
      stat = Google::SearchConsole::Stat
      stat.grouped(period.apply(stat.by_query.site_wide), by: [:query]).to_a
    end
  end

  # The page shown most for each query, from every country, as per-page
  # queries aren't split by one.
  def ranking_pages(queries)
    return {} if queries.empty?

    stat = Google::SearchConsole::Stat
    stat.grouped(period.apply(stat.by_query.per_page.where(:query.in => queries)), by: [:query, :page_path]).to_a
      .group_by { |row| row[:query] }
      .transform_values { |rows| rows.max_by { |row| [row.impressions, row.clicks] }[:page_path] }
  end

  # Nil when an entry answering the query is what ranks for it.
  def reason(words, page_path, closest)
    ranking = page_path && entries_by_path[page_path.chomp("/").presence || "/"]
    if closest.nil?
      "No entry covers it"
    elsif page_path.nil?
      "No page of the blog ranks for it"
    elsif page_path.chomp("/").empty?
      "Only the home page ranks"
    elsif ranking.nil?
      "Only a listing page ranks"
    elsif coverage(words, ranking[:words]) < MIN_COVERAGE
      "Ranks with a loosely matched entry"
    end
  end

  def entries
    @entries ||= FeedEntry.includes(:tags, :categories).map do |entry|
      text = [entry.name, entry.description, *entry.tag_names, *entry.category_names].join(" ")
      {entry: entry, path: IndexCoverage.path_of(entry.url).chomp("/"), words: words_of(text).to_set}
    end
  end

  def entries_by_path
    @entries_by_path ||= entries.index_by { |entry| entry[:path] }
  end

  def coverage(words, entry_words)
    words.count { |word| entry_words.include?(word) }.fdiv(words.size)
  end

  # A trailing s dropped, so "grids" finds "grid"; not from short words or
  # ones ending "ss", where it's part of the word, as in "css" or "class".
  def words_of(text)
    text.to_s.downcase.scan(/[\p{L}\p{N}+#]+/).filter_map do |word|
      word = word.delete_suffix("s") if word.size > 3 && word.end_with?("s") && !word.end_with?("ss")
      word unless STOP_WORDS.include?(word)
    end.uniq
  end
end
