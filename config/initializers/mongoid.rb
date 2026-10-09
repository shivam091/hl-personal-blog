# encoding: UTF-8

Mongoid.configure do
  target_version = "9.1"

  config.load_defaults target_version
end

# Mongoid shares Rails.logger with the driver and ignores mongoid.yml's
# log_level, which floods development logs with driver chatter. A separate
# logger keeps it quiet by default while still allowing queries to be shown
# on demand. After initialization, because Mongoid's railtie assigns its
# logger first.
Rails.application.config.after_initialize do
  mongo_logger = ActiveSupport::BroadcastLogger.new(*Rails.logger.broadcasts.map(&:dup))
  mongo_logger.level = ENV["MONGO_LOG_LEVEL"].presence || "info"
  Mongo::Logger.logger = mongo_logger
end
