# encoding: UTF-8

require "rails_helper"
require "rake"

RSpec.describe "consent rake tasks" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  around { |example| travel_to(Time.zone.parse("2026-10-13 12:00")) { example.run } }

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  it "snapshots the last few days" do
    expect { run("consent:snapshot") }.to output(/Consent snapshots written: 3/).to_stdout

    expect(ConsentSnapshot.pluck(:day).sort).to eq(%w[2026-10-10 2026-10-11 2026-10-12])
  end

  it "backfills a span, to yesterday when no end is given" do
    expect { run("consent:backfill", "2026-10-08") }.to output(/written: 5/).to_stdout
    expect { run("consent:backfill", "2026-10-01", "2026-10-02") }.to output(/written: 2/).to_stdout
  end

  it "refuses a backfill with no start or a backwards span" do
    expect { run("consent:backfill") }.to raise_error(SystemExit).and output(/Usage/).to_stderr
    expect { run("consent:backfill", "2026-10-05", "2026-10-01") }.to raise_error(SystemExit).and output(/must not be after/).to_stderr
  end
end
