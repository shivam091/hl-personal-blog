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
      redirect_back_or_to saved_searches_path, alert: "Couldn't save the search: #{search.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  def destroy
    search = SavedSearch.find(params[:id])
    search.destroy
    redirect_back_or_to saved_searches_path, notice: "Removed the saved search “#{search}”.", status: :see_other
  end
end
