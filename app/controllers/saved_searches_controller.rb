# encoding: UTF-8

class SavedSearchesController < ApplicationController
  def index
    @saved_searches = SavedSearch.all.sort_by(&:name).group_by(&:list)
    @saved_search_lists = SavedSearch.lists
  end

  # Saving under a name already used replaces that search, since a second
  # one with the same name couldn't be told apart.
  def create
    search = SavedSearch.find_or_initialize_by(list: params[:list].to_s, name: params[:name].to_s.squish)
    search.query = params[:query].to_s

    if search.save
      redirect_back_or_to saved_searches_path, notice: "Saved the search “#{search}”.", status: :see_other
    else
      respond_to do |format|
        # Only the form is redrawn, so the list behind it stays as it was
        # while the name is fixed.
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("saved-search-form", partial: "shared/filtering/saved_search_form",
            locals: {list: search.list, query: search.query, search: search}), status: :unprocessable_content
        end
        format.html do
          redirect_back_or_to saved_searches_path, alert: "Couldn't save the search: #{search.errors.full_messages.to_sentence}.", status: :see_other
        end
      end
    end
  end

  def destroy
    search = SavedSearch.find(params[:id])
    search.destroy
    redirect_back_or_to saved_searches_path, notice: "Removed the saved search “#{search}”.", status: :see_other
  end
end
