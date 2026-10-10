# encoding: UTF-8

# Whole class strings, because Tailwind only generates the classes it finds
# written out in full.
module ViewClassesHelper
  EMPTY_NOTE_CLASS = "px-4 py-3 text-sm text-slate-500"
  FOOTNOTE_CLASS = "border-t border-slate-200 px-4 py-2 text-xs text-slate-500"
  LEAD_NOTE_CLASS = "border-b border-slate-200 px-4 py-2 text-xs text-slate-500"
  CARD_FOOTER_CLASS = "flex justify-end border-t border-slate-200 px-4 py-2"
  PAGE_TITLE_CLASS = "text-2xl font-semibold tracking-tight"
  PAGE_HEADER_CLASS = "mb-6 flex flex-wrap items-start justify-between gap-3"
  SPLIT_GRID_CLASS = "mb-6 grid items-start gap-6 lg:grid-cols-2"
  OUTLINE_BUTTON_CLASS = "inline-flex items-center gap-1.5 rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50"
  TABLE_CARD_CLASS = "relative overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm"
  TABLE_HEAD_CLASS = "border-b border-slate-200 bg-slate-50 text-slate-600"
  SUBTITLE_CLASS = "mt-1 text-sm text-slate-500"
  TOOLBAR_CLASS = "flex flex-wrap items-center gap-2"

  def empty_note_class = EMPTY_NOTE_CLASS

  def footnote_class = FOOTNOTE_CLASS

  def lead_note_class = LEAD_NOTE_CLASS

  def card_footer_class = CARD_FOOTER_CLASS

  def page_title_class = PAGE_TITLE_CLASS

  def page_header_class = PAGE_HEADER_CLASS

  def split_grid_class = SPLIT_GRID_CLASS

  def outline_button_class = OUTLINE_BUTTON_CLASS

  def table_card_class = TABLE_CARD_CLASS

  def table_head_class = TABLE_HEAD_CLASS

  def subtitle_class = SUBTITLE_CLASS

  def toolbar_class = TOOLBAR_CLASS
end
