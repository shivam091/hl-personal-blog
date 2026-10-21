# encoding: UTF-8

class ConsentPageGapReportsController < ApplicationController
  SORT_COLUMNS = {
    "gap" => "desc",
    "gap_percent" => "desc",
    "first_party" => "desc",
    "analytics" => "desc",
    "slug" => "asc"
  }.freeze

  def show
    @period = Period.new(params)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :slug)
    @page_gap = PageGap.new(@period)
    @rows = sorted(@page_gap.rows)

    respond_to do |format|
      format.html
      format.csv do
        send_csv @page_gap.to_csv(@rows),
                 filename: "consent-pages-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Consent page gaps, #{@period}"
      end
    end
  end

  private

  # Pages too quiet to have a share lost sort last either way, so a noisy 100% never tops the list.
  def sorted(rows)
    column = @sorting.column
    with_value, without = rows.partition { |row| !sort_value(row, column).nil? }
    with_value = with_value.sort_by { |row| [sort_value(row, column), row.slug] }
    with_value = with_value.reverse if @sorting.direction == "desc"
    with_value + without.sort_by(&:slug)
  end

  def sort_value(row, column)
    case column
    when "gap_percent" then row.percent
    when "slug" then row.slug
    else row.public_send(column)
    end
  end
end
