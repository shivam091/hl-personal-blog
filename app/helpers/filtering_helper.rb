# encoding: UTF-8

module FilteringHelper
  # One shared search UI so every list searches the same way.
  def search_panel(filtering, keep: [])
    sorting = keep.find { |state| state.is_a?(Sorting) }
    list = SavedSearch.list_for(controller_path: controller_path, layout: @layout)
    render "shared/filtering/search_panel", filtering: filtering, keep: keep, sorting: sorting, list: list
  end

  # One shared tab UI so every list's quick filters look and behave alike.
  def filter_tabs(filtering, counts:, keep: [])
    render "shared/filtering/tabs", filtering: filtering, counts: counts, keep: keep
  end
end
