# encoding: UTF-8

Rails.application.routes.draw do
  # Rails' own controller, outside Authentication, so the host's health
  # check reaches it signed out.
  get "up" => "rails/health#show", as: :rails_health_check

  # Rails' own controller, so the browser reaches both signed out.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: {format: "js"}

  resource :session, only: %i[new create destroy]

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
