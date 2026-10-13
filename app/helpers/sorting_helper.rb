# encoding: UTF-8

module SortingHelper
  # Makes column headers the sort control, so sorting is discoverable and
  # its state is visible and announced to screen readers.
  def sort_header(sorting, label, column, keep: [], **options, &block)
    active = sorting.sorted_by?(column)
    arrow = active ? (sorting.direction == "asc" ? "arrow-up" : "arrow-down") : "chevrons-up-down"

    tag.th(scope: "col", aria: {sort: sorting.aria_sort(column)}, **options) do
      link = link_to list_url(*keep, **sorting.toggle_query(column)), class: "group inline-flex items-center gap-1 hover:text-slate-900" do
        safe_join([
          label,
          icon(arrow, size: 14, class: active ? "text-slate-900" : "text-slate-300 group-hover:text-slate-400")
        ])
      end
      block ? safe_join([link, capture(&block)]) : link
    end
  end
end
