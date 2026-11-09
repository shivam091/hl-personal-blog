# encoding: UTF-8

Rails.application.routes.draw do
  # Rails' own controller, outside Authentication, so the host's health
  # check reaches it signed out.
  get "up" => "rails/health#show", as: :rails_health_check

  # Rails' own controller, so the browser reaches both signed out.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: {format: "js"}

  resource :session, only: %i[new create destroy]

  # Their ids are page slugs like "/post/x" (and "/" for the home page), so
  # the slashes are escaped into one segment and dots don't start a format.
  resources :page_views, only: %i[index show], path: "page-views", constraints: {id: /.+/}
  resources :page_likes, only: %i[index show], path: "page-likes", constraints: {id: /.+/}
  resources :newsletter_subscribers, only: %i[index show destroy], path: "newsletter-subscribers"
  resources :messages, only: %i[index show]

  # Reports join the blog's own figures with Google's, so they sit apart from
  # the pages of either source.
  scope "reports" do
    resource :ranking_opportunity_report, only: :show, path: "ranking-opportunities"
  end

  # Ids are entry URLs, so dots mustn't start a format.
  resources :feed_entries, only: %i[index show], path: "feed-entries", constraints: {id: /.+/} do
    post :sync, on: :collection
    post :notify, on: :member
    post :resend, on: :member
  end

  resources :crawled_pages, only: :index, path: "crawled-pages" do
    collection do
      post :sync
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

  # Read-only copies of Google's data: the only writes are syncs from Google,
  # and uploads of the reports Google only exports.
  # A report's breakdown is a required segment, since url_for only carries
  # required ones into sort and page links. The bare path shows the first
  # breakdown in place, so a menu link lands without a redirect.
  namespace :google do
    namespace :search_console, path: "search-console" do
      get "performance", to: "performance#index", defaults: {breakdown: "pages"}, as: :performance
      get "performance/:breakdown", to: "performance#index", as: :performance_breakdown
      post "performance/:breakdown/sync", to: "performance#sync", as: :performance_sync
      resources :sitemaps, only: :index do
        post :sync, on: :collection
        post :submit, on: :collection
      end
      resources :url_inspections, only: %i[index show], path: "url-inspections" do
        post :sync, on: :collection
      end
      get "generative-ai", to: "generative_ai#index", defaults: {breakdown: "pages"}, as: :generative_ai
      get "generative-ai/:breakdown", to: "generative_ai#index", as: :generative_ai_breakdown,
        constraints: {breakdown: /pages|countries|devices|dates/}
      post "generative-ai", to: "generative_ai#create"
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
  resources :saved_searches, only: %i[index create destroy], path: "settings/saved-searches"

  root "dashboard#show"
end
