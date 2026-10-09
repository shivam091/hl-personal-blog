# encoding: UTF-8

require_relative "boot"

require "rails"
# Active Record, the frameworks built on it (Active Storage, Action Text,
# Action Mailbox), and Action Cable are left out because all data lives in
# MongoDB.
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module HLPersonalBlog
  class Application < Rails::Application
    config.load_defaults 8.1

    # Rake tasks and assets hold no constants to autoload.
    config.autoload_lib(ignore: %w[assets tasks])

    # The admin works in India, so times are shown, and days for date
    # filters are counted, in IST. MongoDB still stores UTC.
    config.time_zone = "Asia/Kolkata"

    config.generators do |g|
      g.test_framework :rspec,
                       fixtures: false,
                       view_specs: false,
                       helper_specs: false,
                       routing_specs: false
    end
  end
end
