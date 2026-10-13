# encoding: UTF-8

module FilteringHelper
  def search_panel(filtering, keep: [])
    render "shared/filtering/search_panel", filtering: filtering, keep: keep
  end

  def filter_tabs(filtering, counts:, keep: [])
    render "shared/filtering/tabs", filtering: filtering, counts: counts, keep: keep
  end
end
