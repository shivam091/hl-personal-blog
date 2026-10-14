# encoding: UTF-8

# Exists so each list shows the columns, order, sort and page size the admin
# works with, rather than the ones it was built with.
class ListLayoutsController < ApplicationController
  before_action :set_layout, only: %i[edit update destroy]

  def index
    @layouts = ListLayout.all
    @saved_searches = SavedSearch.all.sort_by(&:name).group_by(&:list)
  end

  def edit
  end

  # Back to the page the dialog was opened over, so a list shows its new
  # layout straight away.
  def update
    @layout.save(params.permit(:sort, :direction, :per_page, :tab, :density, :row_numbers, :sticky_header, shown: [], hidden: []))
    redirect_back_or_to list_layouts_path, notice: "Saved the layout of #{@layout.label.downcase_first}.", status: :see_other
  end

  def destroy
    @layout.reset!
    redirect_back_or_to list_layouts_path, notice: "Reset #{@layout.label.downcase_first} to its default layout.", status: :see_other
  end

  private

  def set_layout
    @layout = ListLayout.find(params[:list])
  end
end
