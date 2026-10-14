# encoding: UTF-8

module FilteringHelper
  def search_panel(filtering, keep: [])
    sorting = keep.find { |state| state.is_a?(Sorting) }
    list = SavedSearch.list_for(controller_path: controller_path, layout: @layout)
    render "shared/filtering/search_panel", filtering: filtering, keep: keep, sorting: sorting, list: list
  end

  def filter_tabs(filtering, counts:, keep: [])
    render "shared/filtering/tabs", filtering: filtering, counts: counts, keep: keep
  end
end
