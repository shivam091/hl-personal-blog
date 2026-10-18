# encoding: UTF-8

require "rails_helper"

RSpec.describe "reCAPTCHA scores", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  def stat(date, scores, actions: {}, challenges: {})
    Google::Recaptcha::Stat.create!(date: date, scores: scores.map { |score, count| {"score" => score, "count" => count} },
      action_scores: actions, challenges: challenges)
  end

  it "lists each day in the last 28, newest first, with the period's totals" do
    stat(yesterday, {0.9 => 6, 0.1 => 2}, actions: {"login" => [{"score" => 0.9, "count" => 6}]}, challenges: {"failed" => 1})
    stat(yesterday - 1, {0.9 => 2})
    stat(yesterday - 28, {0.1 => 50})

    get google_recaptcha_scores_path

    page = Nokogiri::HTML5(response.body)
    rows = page.css("tbody[data-controller=disclosure] > tr:first-child").map { |row| row.css("td").map { |cell| cell.text.squish } }
    expect(rows).to eq([
      ["", "12 Oct, 2026", "8", "25.0%", "0.70", "0.9 6 0.1 2", "1"],
      ["", "11 Oct, 2026", "2", "0.0%", "0.90", "0.9 2", "—"]
    ])
    expect(page.css("dl dd.text-lg").map(&:text)).to eq(["10", "20.0%", "0.74", "1"])
    expect(page.at_css("tbody tr[hidden]").text).to include("login")
    expect(page.at_css("#hint-below-0-5").text).to include("the threshold Google suggests by default")
  end

  it "charts requests by risk, the spread of scores and the top actions, overall or for one action" do
    stat(yesterday, {0.9 => 3, 0.1 => 1}, actions: {"login" => [{"score" => 0.9, "count" => 2}, {"score" => 0.1, "count" => 1}],
      "contact" => [{"score" => 0.9, "count" => 1}]})
    stat(yesterday - 2, {0.9 => 2}, actions: {"contact" => [{"score" => 0.9, "count" => 2}]})

    get google_recaptcha_scores_path(from: "2026-10-10", to: "2026-10-12")

    page = Nokogiri::HTML5(response.body)
    days = page.css("section[aria-labelledby=recaptcha-requests] [data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
    expect(days.map { |day| [day["title"], day["rows"].map { |row| row["value"] }] })
      .to eq([["Sat, 10 Oct 2026", %w[0 2]], ["Mon, 12 Oct 2026", %w[1 3]]])
    expect(page.css("section[aria-labelledby=recaptcha-top-actions] li span[title]").map(&:text)).to eq(%w[contact login])
    expect(page.css("section[aria-labelledby=recaptcha-suspicious-actions] li span[title]").map(&:text)).to eq(%w[login])
    expect(page.css("#recaptcha-action option").map(&:text)).to eq(["Overall traffic", "contact", "login"])

    get google_recaptcha_scores_path(from: "2026-10-10", to: "2026-10-12", recaptcha_action: "login")

    page = Nokogiri::HTML5(response.body)
    days = page.css("section[aria-labelledby=recaptcha-requests] [data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
    expect(days.map { |day| day["rows"].map { |row| row["value"] } }).to eq([%w[0 0], %w[1 2]])
    expect(page.at_css("#recaptcha-action option[selected]").text).to eq("login")
    expect(page.at_css("nav[aria-label=Pagination], a[href*='sort']")&.[]("href").to_s).to include("recaptcha_action=login")
  end

  it "reads requests and each action against the period compared with, day for day, only once one is picked" do
    stat(yesterday - 5, {0.9 => 1}, actions: {"login" => [{"score" => 0.9, "count" => 1}]})
    stat(yesterday - 3, {0.9 => 2, 0.1 => 2}, actions: {"login" => [{"score" => 0.9, "count" => 2}, {"score" => 0.1, "count" => 2}]})
    stat(yesterday, {0.9 => 3, 0.1 => 1}, actions: {"login" => [{"score" => 0.9, "count" => 2}, {"score" => 0.1, "count" => 1}],
      "contact" => [{"score" => 0.9, "count" => 1}]})

    get google_recaptcha_scores_path(from: "2026-10-10", to: "2026-10-12")

    page = Nokogiri::HTML5(response.body)
    days = page.css("section[aria-labelledby=recaptcha-requests] [data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
    # A day with neither has no readout, as without a comparison.
    expect(days.map { |day| [day["title"], day["rows"].last.values_at("name", "value")] }).to eq([
      ["Sat, 10 Oct 2026", ["Previous period", "1"]],
      ["Mon, 12 Oct 2026", ["Previous period", "4"]]
    ])
    expect(page.css("section[aria-labelledby=recaptcha-requests] polyline[data-previous]")).to be_present
    # 12 Oct is the third day, so it's read against 9 Oct.
    rows = page.css("tbody[data-controller=disclosure] > tr:first-child").map { |row| row.css("td").map { |cell| cell.text.squish } }
    expect(rows).to eq([["", "12 Oct, 2026", "4 (0%)", "25.0% (−50%)", "0.70 (+40%)", "0.9 3 0.1 1", "—"]])
    expect(page.at_css("tbody[data-controller=disclosure] td:nth-child(4) span")["class"]).to include("text-emerald-700")
    expect(page.at_css("tbody[data-controller=disclosure] td:nth-child(5) span")["title"]).to eq("Up from 0.50 in the period before")
    actions = ->(id) { page.css("section[aria-labelledby=#{id}] li").map { |row| row.at_css("span.flex").text.squish } }
    expect(actions.("recaptcha-top-actions")).to eq(["login (−40%)", "contact (new)"])
    expect(actions.("recaptcha-suspicious-actions")).to eq(["login (−50%)"])

    get google_recaptcha_scores_path(from: "2026-10-10", to: "2026-10-12", compare: "off")

    page = Nokogiri::HTML5(response.body)
    expect(page.css("section[aria-labelledby=recaptcha-requests] polyline[data-previous]")).to be_empty
    expect(page.css("section[aria-labelledby=recaptcha-top-actions] li span.flex").map { |name| name.text.squish }).to eq(%w[login contact])
  end

  it "leaves out the action picker, cards and expanders when Google split out no actions" do
    stat(yesterday, {0.9 => 4}, actions: {"login" => [{"score" => 0.9, "count" => 4}]})
    stat(yesterday - 1, {0.9 => 2})

    get google_recaptcha_scores_path(from: "2026-10-11", to: "2026-10-11")

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#recaptcha-action")).to be_nil
    expect(page.at_css("#recaptcha-top-actions, #recaptcha-suspicious-actions")).to be_nil
    expect(page.at_css("tbody tr[hidden], tbody button[aria-controls]")).to be_nil
    expect(response.body).not_to include("Google split out no actions")

    get google_recaptcha_scores_path(from: "2026-10-11", to: "2026-10-12")

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#recaptcha-action")).to be_present
    expect(page.css("tbody[data-controller=disclosure] button[aria-expanded]").map { |button| button["aria-label"] }).to eq(["Show actions for 12 Oct, 2026"])
  end

  it "charts challenges and their pass rate only for a key that's challenged" do
    stat(yesterday, {0.9 => 2})

    get google_recaptcha_scores_path
    expect(Nokogiri::HTML5(response.body).at_css("#recaptcha-challenges")).to be_nil

    stat(yesterday - 1, {0.9 => 10}, challenges: {"page_loads" => 10, "no_challenge" => 6, "passed" => 3, "failed" => 1})

    get google_recaptcha_scores_path(from: "2026-10-10", to: "2026-10-12")

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#recaptcha-challenges").parent.text).to include("75.0% of challenges passed")
    days = page.css("section[aria-labelledby=recaptcha-challenges] [data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
    expect(days.map { |day| [day["title"], day["rows"].map { |row| row["value"] }] }).to eq([["Sun, 11 Oct 2026", %w[6 3 1]]])
  end

  it "exports daily scores and scores by action" do
    stat(yesterday, {0.9 => 6}, actions: {"login" => [{"score" => 0.9, "count" => 6}]}, challenges: {"passed" => 3})

    get google_recaptcha_scores_path(format: :csv)
    csv = CSV.parse(response.body, headers: true)
    expect(csv.first.to_h.slice("Date", "Requests", "Score 0.9", "Score 0.1", "Passed")).to eq(
      "Date" => "2026-10-12", "Requests" => "6", "Score 0.9" => "6", "Score 0.1" => "0", "Passed" => "3"
    )

    get google_recaptcha_scores_path(format: :csv, export: "actions")
    expect(response.headers["Content-Disposition"]).to include("recaptcha-scores-by-action-")
    expect(CSV.parse(response.body, headers: true).first.to_h.slice("Date", "Action", "Requests")).to eq(
      "Date" => "2026-10-12", "Action" => "login", "Requests" => "6"
    )
  end

  it "queues a metrics sync" do
    expect { post sync_google_recaptcha_scores_path }.to change(SyncRequest, :count).by(1)
    expect(Google::Recaptcha::MetricsSyncJob).to have_been_enqueued.with(request_id: SyncRequest.find_by(kind: "recaptcha_metrics", trigger: "admin").id.to_s)
    expect(response).to redirect_to(google_recaptcha_scores_path)
  end
end
