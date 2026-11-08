# encoding: UTF-8

source "https://rubygems.org"

gem "rails", "~> 8.1"
gem "propshaft", "~> 1.3"

# The standalone CLI, so building CSS needs no Node.
gem "tailwindcss-rails", "~> 4.6"
gem "puma", "~> 8.0"
gem "importmap-rails", "~> 2.2"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"
gem "jbuilder", "~> 2.15"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Required by config/boot.rb before anything else, so it can cache the whole boot.
gem "bootsnap", "~> 1.26", require: false

gem "thruster", "~> 0.1", require: false

# The blog's data lives in MongoDB, shared with its frontend.
gem "mongoid", "~> 9.1"

gem "haml-rails", "~> 3.1"

# The blog frontend calls the API from another origin.
gem "rack-cors", "~> 3.0"

# No longer a default gem as of Ruby 3.4.
gem "csv", "~> 3.3"

gem "faraday", "~> 2.15"

# Search Console exports its generative AI report only as a spreadsheet, so
# it's read from an uploaded one.
gem "roo", "~> 4.0"

group :development, :test do
  gem "rspec-rails", "~> 8.0"
  gem "database_cleaner-mongoid", "~> 2.0"
  gem "debug", "~> 1.11", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", "~> 0.9", require: false
  gem "brakeman", "~> 8.1", require: false
  gem "rubocop-rails-omakase", "~> 1.1", require: false
end

group :development do
  gem "web-console", "~> 4.3"
end

group :test do
  gem "capybara", "~> 3.40"
  gem "selenium-webdriver", "~> 4.51"
end
