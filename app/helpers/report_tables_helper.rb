# encoding: UTF-8

module ReportTablesHelper
  REPORT_TABLE_CLASS = "w-full border-collapse text-sm"
  REPORT_HEADING_CLASS = "px-3 py-1.5 font-medium whitespace-nowrap"
  REPORT_CELL_CLASS = "px-3 py-1.5 text-right tabular-nums"
  EXPORT_LINK_CLASS = "inline-flex items-center gap-1 text-xs font-medium text-slate-600 hover:text-slate-900 hover:underline"
  FILTER_SELECT_CLASS = "h-8 rounded-md border border-slate-300 bg-white px-2.5 py-0 text-sm font-normal text-slate-900 shadow-sm focus:border-slate-500 focus:ring-1 focus:ring-slate-500 focus:outline-none"

  def table_class = REPORT_TABLE_CLASS

  def th_class = REPORT_HEADING_CLASS

  def cell_class = REPORT_CELL_CLASS

  def export_class = EXPORT_LINK_CLASS

  def select_class = FILTER_SELECT_CLASS

  # Every report table's header cell differs only in its text, alignment and
  # tooltip, so the scope and spacing live in one place.
  def report_th(content = nil, align = :left, **attributes, &block)
    tag.th(content, scope: "col", class: [th_class, "text-#{align}"], **attributes, &block)
  end
end
