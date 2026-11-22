# encoding: UTF-8

namespace :consent do
  desc "Snapshot the last few days' views against GA's, with what the gap is put down to"
  task snapshot: :environment do
    puts "Consent snapshots written: #{ConsentSnapshotJob.perform_now(trigger: "rake")}"
  end

  desc "Snapshot every day from one date to another (ISO dates; the second defaults to yesterday)"
  task :backfill, [:from, :to] => :environment do |_, args|
    abort "Usage: bin/rails consent:backfill[2026-10-01,2026-10-31]" if args[:from].blank?

    from = Date.iso8601(args[:from])
    to = args[:to].present? ? Date.iso8601(args[:to]) : Date.current - 1
    abort "From must not be after to" if from > to

    puts "Consent snapshots written: #{ConsentSnapshotJob.perform_now(from: from, to: to, trigger: "rake")}"
  end
end
