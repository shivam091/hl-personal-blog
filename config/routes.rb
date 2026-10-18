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

  # Reports join the blog's own figures with Google's, so they sit apart from
  # the pages of either source.
  scope "reports" do
    resource :ranking_report, only: :show, path: "ranking-opportunities"
  end

  # Ids are entry URLs, so dots mustn't start a format.
  resources :feed_entries, only: %i[index show destroy], path: "feed-entries", constraints: {id: /.+/} do
    post :import, on: :collection
    post :sync, on: :collection
    post :notify, on: :member
    post :resend, on: :member
  end

  resources :crawled_pages, except: :show, path: "crawled-pages" do
    collection do
      post :import
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

  # Read-only copies of Google's data: the only writes are syncs from Google.
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
    end

    # Paths named after GA's own report sections, so a page is found where it
    # would be in GA.
    namespace :analytics do
      get "acquisition", to: "acquisition#index", defaults: {breakdown: "user-acquisition"}, as: :acquisition
      get "acquisition/:breakdown", to: "acquisition#index", as: :acquisition_breakdown
      post "acquisition/:breakdown/sync", to: "acquisition#sync", as: :acquisition_sync
      get "engagement", to: "engagement#index", defaults: {breakdown: "events"}, as: :engagement
      # Under Engagement, as GA opens an event from its Events report. Any
      # character but a slash, since GA's names can hold dots.
      get "engagement/events/:event_name", to: "event_details#show", as: :event, constraints: {event_name: %r{[^/]+}}, format: false
      get "engagement/:breakdown", to: "engagement#index", as: :engagement_breakdown
      post "engagement/:breakdown/sync", to: "engagement#sync", as: :engagement_sync
      get "users", to: "users#index", defaults: {breakdown: "countries"}, as: :users
      get "users/:breakdown", to: "users#index", as: :users_breakdown
      post "users/:breakdown/sync", to: "users#sync", as: :users_sync
      get "retention", to: "retention#index", defaults: {breakdown: "new-vs-returning"}, as: :retention
      # Apart from Retention's breakdowns, since a cohort is asked of GA live.
      get "cohorts", to: "cohorts#show", as: :cohorts
      get "retention/:breakdown", to: "retention#index", as: :retention_breakdown
      post "retention/:breakdown/sync", to: "retention#sync", as: :retention_sync
      get "realtime", to: "realtime#show", as: :realtime
      get "funnels", to: "funnels#show", as: :funnels
      get "site-search", to: "site_searches#show", as: :site_search
      get "settings", to: "settings#show", as: :settings
      post "settings/custom-dimensions", to: "settings#register_dimension", as: :settings_custom_dimensions
      post "settings/annotations", to: "settings#annotate", as: :settings_annotations
      get "quota", to: "quotas#show", as: :quota
    end

    namespace :recaptcha do
      resources :stats, only: :index, path: "scores" do
        post :sync, on: :collection
      end
      resources :assessments, only: %i[index show]
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

  root "dashboard#show"
end
