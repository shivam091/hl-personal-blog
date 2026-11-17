# encoding: UTF-8

namespace :page_views do
  desc "Estimate page views and unique visitors before the blog counted them from Google Analytics; prints the estimate, and only writes with WRITE=1"
  task backfill: :environment do
    guard_live_database!
    write = ENV["WRITE"] == "1"
    result = PageViewBackfill.call(write: write)

    puts "Views factor #{result.views_factor.round(3)}, visitors factor #{result.visitors_factor.round(3)}"
    result.by_month.each { |month, counts| puts "  #{month}: #{counts[:views]} views, #{counts[:visitors]} unique visitors" }
    puts "#{write ? "Wrote" : "Would write"} #{result.views} views and #{result.visitors} unique visitors over #{result.days} page days on #{result.pages} pages"
    puts "#{write ? "Wrote" : "Would write"} devices and referrers for #{result.breakdown_days} page days"
    puts "Left out #{result.skipped_views} Google Analytics views on paths with no page view record"
  end

  desc "Remove what page_views:backfill wrote"
  task unbackfill: :environment do
    guard_live_database!
    PageViewBackfill.revert
    puts "Removed the backfilled page views and visitor markers"
  end

  # Shared with the blog frontend, so writing there takes a deliberate yes.
  def guard_live_database!
    abort "Refusing to touch the live database; set LIVE=yes to." if Rails.env.production? && ENV["LIVE"] != "yes"
  end
end
