# encoding: UTF-8

namespace :monitoring do
  desc "Delete request logs and external calls from before today"
  task clear: :environment do
    MonitoringReview.clear.each { |name, count| puts "Cleared #{count} #{name.to_s.tr("_", " ")}" }
  end
end
