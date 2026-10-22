# encoding: UTF-8

# Every entry ranked on each measure there is of it, so one strong on all
# of them stands out from one that merely has the most views, and one
# Google shows often but that underperforms stands out as worth the work.
class ContentScorecard
  Measure = Struct.new(:key, :label, :format, keyword_init: true)

  MEASURES = [
    Measure.new(key: :views, label: "Views", format: :count),
    Measure.new(key: :like_rate, label: "Likes per view", format: :rate),
    Measure.new(key: :clicks, label: "Search clicks", format: :count),
    Measure.new(key: :ctr, label: "Search CTR", format: :rate),
    Measure.new(key: :engagement, label: "Time engaged", format: :duration),
    Measure.new(key: :read_through, label: "Read-through", format: :rate),
    Measure.new(key: :performance, label: "Speed", format: :score)
  ].freeze
  SORTS = {"score" => "Best overall", "potential" => "Most potential"}.freeze
  UNKNOWN_RANK = 0.5

  Row = Struct.new(:item, :values, :ranks, :score, :potential, keyword_init: true)

  # AI impressions are shown beside the measures but never ranked, since
  # they're Google's totals over the latest upload's range, not the period's.
  def initialize(content, ai: nil)
    @content = content
    @ai = ai
  end

  def ai_impressions(row)
    @ai.pages.fetch(row.item.path, 0) if @ai&.covered
  end

  # Ranked among the entries of the period before, so a score is set against
  # what it was then rather than against today's field.
  def previous
    return @previous if defined?(@previous)

    earlier = @content.previous
    @previous = (self.class.new(earlier) if earlier)
  end

  def previous_row(row)
    previous&.send(:ranked_by_path)&.[](row.item.path)
  end

  def rows(sort: "score")
    key = SORTS.key?(sort) ? sort.to_sym : :score
    ranked.sort_by { |row| [-row.public_send(key).to_f, row.item.path] }
  end

  # Each measure's own figure beside its rank, so a spreadsheet can be
  # sorted by either.
  def to_csv(sort: "score")
    CSV.generate do |csv|
      ai_heading = "AI impressions #{@ai.covered.begin.iso8601} to #{@ai.covered.end.iso8601}" if @ai&.covered
      csv << ["URL", "Title", "Type", "Published", "Score", "Potential", *MEASURES.flat_map { |measure| [measure.label, "#{measure.label} rank"] },
        *ai_heading]
      rows(sort: sort).each do |row|
        entry = row.item.entry
        before = previous_row(row)
        compared = !previous.nil?
        # Speed is a snapshot, so it has no earlier figure to be set against.
        csv << [entry.url, entry.name, entry.type, entry.published_at&.utc&.iso8601,
          CompareChange.cell(row.score&.round(4), before&.score&.round(4), compare: compared),
          CompareChange.cell(row.potential&.round(4), before&.potential&.round(4), compare: compared),
          *MEASURES.flat_map do |measure|
            [CompareChange.cell(row.values[measure.key]&.round(4), before&.values&.[](measure.key)&.round(4), compare: compared && measure.key != :performance),
              row.ranks[measure.key]&.round(4)]
          end, *(ai_impressions(row) if ai_heading)]
      end
    end
  end

  private

  # Percentile ranks within each measure, among entries that have it, so
  # views in the thousands and a CTR in hundredths weigh the same. A measure
  # an entry lacks counts as middling, so one strong on two measures can't
  # outrank one strong on five, nor be sunk by what isn't known.
  def ranked
    @ranked ||= begin
      values = @content.items.to_h { |item| [item, measures(item)] }
      ranks = MEASURES.to_h { |measure| [measure.key, percentile_ranks(values.transform_values { |row| row[measure.key] })] }
      impressions = percentile_ranks(@content.items.to_h { |item| [item, (item.impressions if item.impressions.positive?)] })
      values.map do |item, row|
        item_ranks = MEASURES.to_h { |measure| [measure.key, ranks[measure.key][item]] }.compact
        score = (item_ranks.values.sum + UNKNOWN_RANK * (MEASURES.size - item_ranks.size)) / MEASURES.size if item_ranks.any?
        Row.new(item: item, values: row, ranks: item_ranks, score: score,
          # Seen often in search, yet weak: where effort pays back most.
          potential: (impressions[item] * (1 - score) if impressions[item] && score))
      end
    end
  end

  def ranked_by_path
    @ranked_by_path ||= ranked.index_by { |row| row.item.path }
  end

  def measures(item)
    reading = reading_rows[item.path]
    {
      views: (item.views if item.views.positive?),
      like_rate: (item.likes.fdiv(item.views) if item.views >= BlogStats::MIN_VIEWS_FOR_RATE),
      clicks: (item.clicks if item.impressions.positive?),
      ctr: (item.clicks.fdiv(item.impressions) if item.impressions >= Google::SearchConsole::Summary::MIN_IMPRESSIONS),
      engagement: reading&.engagement_seconds_per_reader,
      read_through: (reading.read_through if reading && @content.scrolls?),
      performance: speeds[item.path]
    }
  end

  def reading_rows
    @reading_rows ||= @content.reading(limit: nil).index_by { |row| row.item.path }
  end

  # Phones', as most readers come on one.
  def speeds
    @speeds ||= Google::PageSpeed::Result.where(strategy: "mobile", :performance.ne => nil).pluck(:page_path, :performance).to_h
  end

  # Ties share the middle of the places they span, so equal values rank
  # equally whatever order they came in.
  def percentile_ranks(values)
    known = values.compact
    return {} if known.empty?
    return known.transform_values { 1.0 } if known.size == 1

    sorted = known.values.sort
    known.transform_values do |value|
      below = sorted.bsearch_index { |other| other >= value }
      equal = sorted.count(value)
      (below + (equal - 1) / 2.0) / (sorted.size - 1)
    end
  end
end
