# encoding: UTF-8

# Pages whose share seen by GA moved between a period and the one it's compared with, so a page rising or
# falling in GA's views can be told apart from one whose tracking changed under it.
class PageGapShift
  # As fractions of the blog's own views, so two periods with different traffic can still be compared.
  Shift = Struct.new(:before, :now, keyword_init: true)

  def initialize(period)
    @period = period
  end

  # Another country over the same days isn't a change over time, and the gap isn't split by country.
  def active?
    @period.compare? && !@period.compare_countries?
  end

  # Nil unless both periods had enough views on the page to judge.
  def [](path)
    shifts[self.class.slug_of(path)]
  end

  def shifts
    @shifts ||= active? ? moved : {}
  end

  # The blog names a page without its trailing slash and GA by the address it was loaded at.
  def self.slug_of(path)
    path.to_s.sub(/[?#].*\z/, "").chomp("/").presence || "/"
  end

  private

  def moved
    before = percents(@period.previous)
    percents(@period).each_with_object({}) do |(slug, now), shifts|
      earlier = before[slug]
      next if earlier.nil? || (now - earlier).abs < PageGap::MARGIN

      shifts[slug] = Shift.new(before: 1 - earlier, now: 1 - now)
    end
  end

  def percents(period)
    PageGap.new(period).rows.each_with_object({}) { |row, percents| percents[row.slug] = row.percent unless row.percent.nil? }
  end
end
