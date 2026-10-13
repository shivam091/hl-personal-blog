# encoding: UTF-8

module ReportTablesHelper
  REPORT_TABLE_CLASS = "w-full border-collapse text-sm"
  REPORT_HEADING_CLASS = "px-3 py-1.5 font-medium whitespace-nowrap"
  REPORT_CELL_CLASS = "px-3 py-1.5 text-right tabular-nums"
  EXPORT_LINK_CLASS = "inline-flex items-center gap-1 text-xs font-medium text-slate-600 hover:text-slate-900 hover:underline"
  FILTER_SELECT_CLASS = "h-8 rounded-md border border-slate-300 bg-white px-2.5 py-0 text-sm font-normal text-slate-900 shadow-sm focus:border-slate-500 focus:ring-1 focus:ring-slate-500 focus:outline-none"
  TABLE_ROW_CLASS = "border-t border-slate-200"
  TITLE_CELL_CLASS = "w-full px-3 py-1.5"
  NAME_CELL_CLASS = "px-3 py-1.5 font-medium"
  MUTED_CELL_CLASS = "px-3 py-2 whitespace-nowrap text-slate-500"
  MUTED_NUMBER_CELL_CLASS = "px-3 py-2 text-right tabular-nums text-slate-500"
  LIST_HEADING_CLASS = "px-3 py-2.5 font-semibold"
  LIST_HEADING_RIGHT_CLASS = "px-3 py-2.5 text-right font-semibold"

  def table_class = REPORT_TABLE_CLASS

  def th_class = REPORT_HEADING_CLASS

  def cell_class = REPORT_CELL_CLASS

  def export_class = EXPORT_LINK_CLASS

  def select_class = FILTER_SELECT_CLASS

  def table_row_class = TABLE_ROW_CLASS

  def title_cell_class = TITLE_CELL_CLASS

  def name_cell_class = NAME_CELL_CLASS

  def muted_cell_class = MUTED_CELL_CLASS

  def muted_number_cell_class = MUTED_NUMBER_CELL_CLASS

  def list_heading_class = LIST_HEADING_CLASS

  def list_heading_right_class = LIST_HEADING_RIGHT_CLASS

  def report_table(heads, &rows)
    tag.div(class: "overflow-x-auto") do
      tag.table(class: table_class) do
        safe_join([tag.thead(class: "text-slate-500") { tag.tr { safe_join(heads) } }, tag.tbody { capture(&rows) }])
      end
    end
  end

  def csv_footer(url, label = "CSV")
    tag.p(class: card_footer_class) do
      link_to(url, class: export_class) { safe_join([icon("download", size: 12), label], "\n") }
    end
  end

  def report_th(content = nil, align = :left, **attributes, &block)
    tag.th(content, scope: "col", class: [th_class, "text-#{align}"], **attributes, &block)
  end
end
