# encoding: UTF-8

# The blog frontend runs on another origin, so browsers block its API calls
# unless its origin is allowed here.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins Rails.application.credentials.dig(:cors, :origins) || ["http://localhost:3000"]

    resource "/api/*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: false
  end
end
