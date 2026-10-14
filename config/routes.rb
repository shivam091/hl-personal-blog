# encoding: UTF-8

Rails.application.routes.draw do
  # Rails' own controller, outside Authentication, so the host's health
  # check reaches it signed out.
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[new create destroy]

  # Their ids are page slugs like "/post/x" (and "/" for the home page), so
  # the slashes are escaped into one segment and dots don't start a format.
  resources :page_views, only: %i[index show], path: "page-views", constraints: {id: /.+/}
  resources :page_likes, only: %i[index show], path: "page-likes", constraints: {id: /.+/}
  resources :newsletter_subscribers, only: %i[index show destroy], path: "newsletter-subscribers"
  resources :messages, only: %i[index show]

  # Ids are entry URLs, so dots mustn't start a format.
  resources :feed_entries, only: %i[index show destroy], path: "feed-entries", constraints: {id: /.+/} do
    post :import, on: :collection
    post :notify, on: :member
    post :resend, on: :member
  end

  resources :crawled_pages, except: :show, path: "crawled-pages" do
    collection do
      post :import
      # Ticked rows go to the collection route, so marking several is one
      # request rather than one per row.
      patch :mark_indexed, path: "indexed"
      patch :mark_not_indexed, path: "not-indexed"
      patch :request_indexing, path: "request-indexing"
    end

    member do
      patch :mark_indexed, path: "indexed"
      patch :mark_not_indexed, path: "not-indexed"
      patch :request_indexing, path: "request-indexing"
      post :inspect_url, path: "inspect"
    end
  end

  resources :request_logs, only: %i[index show destroy], path: "request-logs" do
    collection do
      post :clear
      delete :destroy_selected, path: "selected"
    end
  end

  resources :sync_requests, only: %i[index destroy], path: "sync-requests" do
    post :resync, on: :member
    delete :destroy_selected, on: :collection, path: "selected"
  end

  resources :external_calls, only: %i[index destroy], path: "external-calls" do
    delete :destroy_selected, on: :collection, path: "selected"
  end

  # Re-exporting is following the stored export URL, so there's no action
  # for it here.
  resources :export_requests, only: %i[index destroy], path: "export-requests" do
    delete :destroy_selected, on: :collection, path: "selected"
  end

  # Keyed by list rather than an id, since each list has at most one setting
  # and resetting one deletes it.
  resources :list_settings, only: %i[index edit update destroy], path: "settings/lists", param: :list
  resources :saved_searches, only: %i[create destroy], path: "settings/saved-searches"

  root "dashboard#show"
end
