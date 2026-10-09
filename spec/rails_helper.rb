# encoding: UTF-8

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require_relative '../config/environment'

# Specs wipe every collection, which must never happen to production's.
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "database_cleaner/mongoid"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

RSpec.configure do |config|
  # No Active Record in this app - all data lives in MongoDB via Mongoid.
  config.use_active_record = false

  config.filter_rails_from_backtrace!

  # Examples must not see each other's documents; :deletion because
  # database_cleaner-mongoid has no :truncation.
  config.before(:suite) do
    DatabaseCleaner[:mongoid].strategy = :deletion
    DatabaseCleaner[:mongoid].clean_with(:deletion)
  end

  config.around(:each) do |example|
    DatabaseCleaner[:mongoid].cleaning { example.run }
  end
end
