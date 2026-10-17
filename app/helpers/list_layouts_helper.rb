# encoding: UTF-8

module ListLayoutsHelper
  # Headers follow the saved layout, so a list's body only has to draw its
  # cells in the same order.
  def column_headers(layout, sorting, keep: [])
    safe_join(layout.visible_columns.map do |column|
      classes = ["px-3 py-2.5 font-semibold", ("text-right" if column.align == "right")]
      if column.sortable?
        sort_header(sorting, column.label, column.key, keep: keep, class: classes)
      else
        tag.th(column.label, scope: "col", class: classes)
      end
    end)
  end

  # A fixed header needs the list to scroll inside its own box, since
  # sticky stops at the nearest scrolling ancestor.
  def list_container_class(layout)
    ["relative overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm", ("max-h-[75vh] overflow-y-auto" if layout&.sticky_header?)]
  end

  # Set on the table rather than each cell, so every list gets the density
  # without its cells knowing about it.
  def list_table_class(layout)
    ["w-full border-collapse text-left text-sm", ("[&_td]:py-1 [&_th]:py-1.5" if layout&.compact?)]
  end

  def list_head_class(layout)
    ["border-b border-slate-200 bg-slate-50 text-slate-600", ("sticky top-0 z-10 shadow-[0_1px_0_var(--color-slate-200)]" if layout&.sticky_header?)]
  end

  def saved_searches(layout, filtering, sorting)
    render "shared/saved_searches", layout: layout, filtering: filtering, sorting: sorting
  end

  def columns_button(layout)
    link_to edit_list_setting_path(layout.key), data: {turbo_frame: "modal"},
      title: "Choose, order and sort this list's columns",
      class: "inline-flex items-center gap-1.5 rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50" do
      safe_join([icon("columns", size: 14), "Columns"])
    end
  end

  # A short reading of a layout, so lists can be compared on the settings
  # page without opening each.
  def sort_summary(layout)
    key, direction = layout.default_sort
    column = layout.sortable_columns.find { |candidate| candidate.key == key }
    return "Unsorted" unless column

    "#{column.label}, #{direction == "asc" ? "ascending" : "descending"}"
  end
end
