# encoding: UTF-8

module PeriodCountsHelper
  # Unique visitors are hashed per day and only summed all time, so a span
  # has no such figure to show.
  VISITOR_COLUMNS = {true => %w[visitor_count unique_visitor_count], false => %w[visitor_count]}.freeze
  CELL_CLASS = "px-3 py-2 text-right tabular-nums"

  def period_note(period, text)
    tag.p(text, class: "text-xs tabular-nums text-slate-500") unless period.all_time?
  end

  def period_countries(record, period)
    period.all_time? ? record.countries : record.countries_within(period)
  end

  def visitor_headers(period, sorting, keep:)
    safe_join(VISITOR_COLUMNS.fetch(period.all_time?).map do |column|
      sort_header(sorting, PageView.human_attribute_name(column), column, keep: keep, class: "px-3 py-2.5 text-right font-semibold")
    end)
  end

  def visitor_cells(page_view, period)
    counts = period.all_time? ? [page_view.visitor_count, page_view.unique_visitor_count] : [page_view.views_within(period)]
    safe_join(counts.map { |count| tag.td(number_with_delimiter(count), class: CELL_CLASS) })
  end

  # The row number, page and updated-at cells sit beside the count cells.
  def page_view_details_colspan(period)
    VISITOR_COLUMNS.fetch(period.all_time?).size + 2
  end

  def like_count_cell(page_like, period)
    tag.td(number_with_delimiter(period.all_time? ? page_like.like_count : page_like.likes_within(period)), class: CELL_CLASS)
  end
end
