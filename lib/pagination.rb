# encoding: UTF-8

# Exists so admin lists never load a whole collection into one page, and
# so every list pages the same way from the URL.
class Pagination
  DEFAULT_PER_PAGE_OPTIONS = [25, 50, 100, 500].freeze

  attr_reader :page, :per_page, :per_page_options, :total_count

  def initialize(scope, params, per_page_options: DEFAULT_PER_PAGE_OPTIONS, default_per_page: nil)
    @scope = scope
    @per_page_options = per_page_options
    @default_per_page = default_per_page.presence_in(per_page_options) || per_page_options.first
    @per_page = params[:per_page].to_i.presence_in(per_page_options) || @default_per_page
    @total_count = scope.count
    @page = params[:page].to_i.clamp(1, total_pages)
  end

  def records
    @scope.skip((page - 1) * per_page).limit(per_page)
  end

  def total_pages
    [(total_count.to_f / per_page).ceil, 1].max
  end

  def previous_page
    page - 1 if page > 1
  end

  def next_page
    page + 1 if page < total_pages
  end

  # Tells the reader which slice of the results they're looking at.
  def first_item
    total_count.zero? ? 0 : ((page - 1) * per_page) + 1
  end

  def last_item
    [page * per_page, total_count].min
  end

  # Keeps the page links short on long lists while still letting the reader
  # jump to either end.
  def window(around: 2)
    numbers = ([1, total_pages] + ((page - around)..(page + around)).to_a)
      .select { |number| number.between?(1, total_pages) }.uniq.sort

    numbers.each_with_object([]) do |number, window|
      window << nil if window.last && number > window.last + 1
      window << number
    end
  end

  # So links that change filtering or sorting keep the chosen page size but
  # start again from page 1, where the new results begin.
  def query
    per_page_query(per_page)
  end

  # Page links must keep the page size, and page 1 needs no param.
  def page_query(number)
    query.merge(page: (number if number > 1)).compact
  end

  # Changing the page size restarts from page 1, since the old page number
  # no longer points at the same records.
  def per_page_query(size)
    {per_page: (size unless size == @default_per_page)}.compact
  end
end
