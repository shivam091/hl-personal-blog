# encoding: UTF-8

namespace :mixpanel do
  desc "Create and update Mixpanel page, site and frustration stats for the last N days (default 3, credentials mixpanel.*): bin/rails 'mixpanel:sync[days]'"
  task :sync, [:days] => :environment do |_task, args|
    days = (args[:days].presence || Mixpanel::SyncService::DEFAULT_DAYS).to_i
    # Synchronous, as for the Google tasks, since the process exits when it's done.
    result = SyncRequest.track("mixpanel", trigger: "rake", **SyncRequest.range(days)) { Mixpanel::SyncService.call(days: days) }
    puts "Mixpanel sync: #{result.summary}"
    result.errors.each { |error| warn "  #{error}" }
    exit 1 if result.failed?
  end
end
