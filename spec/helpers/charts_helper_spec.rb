# encoding: UTF-8

require "rails_helper"

RSpec.describe ChartsHelper, type: :helper do
  def html(markup)
    Nokogiri::HTML5.fragment(markup)
  end

  def tips(node)
    node.css("[data-chart-tooltip-target=hit]").map { |hit| JSON.parse(hit["data-tip"]) }
  end

  describe "#world_map" do
    it "shades countries on a log scale, greys out empty ones and lists those too small to draw" do
      map = html(helper.world_map({"IN" => 1000, "US" => 10, "VA" => 4, "ZZ" => 7}, label: "Views by country", unit: "view"))
      india = map.css("g[data-tip]").find { |group| JSON.parse(group["data-tip"])["title"] == "India" }
      brazil = map.css("g[data-tip]").find { |group| JSON.parse(group["data-tip"])["title"] == "Brazil" }

      expect(india.at_css("path")["class"]).to include("fill-[#0d366b]", "group-hover:fill-sky-200")
      expect(JSON.parse(india["data-tip"])["rows"]).to eq([{"value" => "1,000", "name" => "views"}])
      expect(brazil.at_css("path")["class"]).to include("fill-[#f0efec]")
      expect(map.at_css("figcaption").text).to include("VA 4")
      expect(map.at_css("figcaption").text).not_to include("ZZ")
    end

    it "marks a country too small to point at with a dot shaded like its shape" do
      map = html(helper.world_map({"SG" => 5}, label: "Views by country", unit: "view"))
      singapore = map.css("g[data-tip]").find { |group| JSON.parse(group["data-tip"])["title"] == "Singapore" }

      expect(singapore.at_css("circle")["class"]).to include("fill-[#0d366b]")
      expect(map.at_css("figcaption")).to be_nil
    end
  end

  describe "#share_chart" do
    let(:shares) do
      {keys: %w[IN US], unit: :week,
       buckets: {Date.new(2026, 10, 5) => {"IN" => 6, "US" => 2, other: 2}, Date.new(2026, 10, 12) => {"IN" => 1, other: 1}}}
    end

    it "stacks each bucket to the full height with Other at the base" do
      chart = html(helper.share_chart(shares, y_title: "Share of views", label: "Shares"))
      segments = chart.css("svg[role=img] > rect:not([data-chart-tooltip-target])").first(3)

      expect(segments.map { |rect| rect["class"][/fill-\[#\h+\]/] }).to eq(%w[fill-[#a8a7a1] fill-[#2a78d6] fill-[#eb6834]])
      expect(segments.sum { |rect| rect["height"].to_f }).to be_within(0.05).of(ChartsHelper::CHART_HEIGHT)
      expect(chart.css("ul li").map(&:text)).to eq(["🇮🇳 IN", "🇺🇸 US", "Other"])
    end

    it "reads out every country in a bar, biggest first and Other last" do
      tip = tips(html(helper.share_chart(shares, y_title: "Share of views", label: "Shares"))).first

      expect(tip["title"]).to eq("Week of 5 Oct, 2026")
      expect(tip["rows"].map { |row| [row["value"], row["name"], row["color"]] }).to eq([
        ["60.0%", "🇮🇳 IN · 6 views", "#2a78d6"], ["20.0%", "🇺🇸 US · 2 views", "#eb6834"], ["20.0%", "Other · 2 views", "#a8a7a1"]
      ])
    end

    it "says so when there's nothing to split" do
      expect(helper.share_chart({keys: [], unit: :week, buckets: {}}, y_title: "Share of views", label: "Shares")).to include("No views in this period.")
    end
  end

  describe "#line_chart" do
    it "marks where each line starts and ends, skipping days without data, and a line of one point once" do
      days = (Date.new(2026, 9, 1)..Date.new(2026, 9, 4)).to_a
      chart = html(helper.line_chart(days, [
        ChartsHelper::Series.new(name: "Total", values: [nil, 10, 20, 5], dotted: true),
        ChartsHelper::Series.new(name: "scroll", values: [nil, nil, 8, nil], color: "#2a78d6")
      ], y_title: "Events", label: "Events per day"))

      expect(chart.css("span[data-series]").map { |marker| [marker["data-series"], marker["style"][/left: [\d.]+%; top: [\d.]+%/]] })
        .to eq([["0", "left: 33.33%; top: 50.0%"], ["0", "left: 100.0%; top: 75.0%"], ["1", "left: 66.67%; top: 60.0%"]])
      expect(chart.css("span[data-series='1']").first["style"]).to include("background-color: #2a78d6")
    end

    it "keys a line with a shape of its own, in the legend, at its ends and in its readout" do
      days = (Date.new(2026, 9, 1)..Date.new(2026, 9, 2)).to_a
      chart = html(helper.line_chart(days, [
        ChartsHelper::Series.new(name: "Total", values: [4, 6], dotted: true, marker: :drop),
        ChartsHelper::Series.new(name: "google", values: [1, 2], color: "#2a78d6", marker: :square)
      ], y_title: "Clicks", label: "Clicks per day", selectable: true))

      expect(chart.css("ul button path").map { |path| [path["d"], path["fill"]] })
        .to eq([[ChartsHelper::MARKERS[:drop], "#1e293b"], [ChartsHelper::MARKERS[:square], "#2a78d6"]])
      expect(chart.css("span[data-series='1'] path").map { |path| path["d"] }).to eq([ChartsHelper::MARKERS[:square]] * 2)
      expect(tips(chart).first["rows"].map { |row| row["marker"] }).to eq(%w[drop square])
    end

    it "runs each line from axis to axis, its first and last days ticked at the edges" do
      days = (Date.new(2026, 9, 1)..Date.new(2026, 9, 4)).to_a
      chart = html(helper.line_chart(days, [ChartsHelper::Series.new(name: "Views", values: [1, 2, 3, 4])], y_title: "Views", label: "Views"))

      expect(chart.at_css("polyline")["points"]).to eq("0.0,90.0 200.0,60.0 400.0,30.0 600.0,0.0")
      expect(chart.css("div.ml-14[aria-hidden] span.w-px").map { |tick| tick["style"] }).to eq(["left: 0.0%", "left: 33.33%", "left: 66.67%", "left: 100.0%"])
      expect(chart.css("rect[data-tip]").map { |hit| [hit["x"], hit["width"]] }).to eq([["0.0", "100.0"], ["100.0", "200.0"], ["300.0", "200.0"], ["500.0", "100.0"]])
    end

    let(:days) { (Date.new(2026, 9, 1)..Date.new(2026, 9, 28)).to_a }

    it "reads out every series on a day, with where each sits for the markers" do
      chart = html(helper.line_chart(days, [
        ChartsHelper::Series.new(name: "This period", values: Array.new(28) { |i| i }),
        ChartsHelper::Series.new(name: "Period before", values: [nil] * 28, dashed: true)
      ], y_title: "Views", label: "Views"))
      tip = tips(chart)[27]

      expect(tips(chart).size).to eq(28)
      expect(tip["title"]).to eq("Mon, 28 Sep 2026")
      expect(tip["rows"]).to eq([
        {"value" => "27", "name" => "This period", "color" => "#1e293b", "y" => 0.0},
        {"value" => "No data", "name" => "Period before", "color" => "#94a3b8", "dashed" => true}
      ])
      expect(chart.at_css("[data-chart-tooltip-target=crosshair]")).to be_present
    end
  end

  describe "#line_chart events" do
    it "marks each event's day on the axis, keys it, and names it in that day's readout" do
      days = (Date.new(2026, 9, 1)..Date.new(2026, 9, 3)).to_a
      chart = html(helper.line_chart(days, [ChartsHelper::Series.new(name: "Views", values: [1, 2, 3])], y_title: "Views", label: "Views",
        events: {days.last => ["A post"], Date.new(2026, 8, 1) => ["Off the chart"]}, event_name: "Published"))

      expect(chart.css("span[data-event]").map { |mark| mark["style"] }).to eq(["left: 100.0%"])
      expect(chart.css("ul li").map(&:text)).to eq(["Views", "Published"])
      expect(tips(chart).last["rows"].last).to eq("value" => "Published", "name" => "A post", "color" => "#eb6834", "marker" => "triangle")
      expect(tips(chart).last["rows"].first["name"]).to eq("Views")
    end
  end

  describe "#line_chart shading" do
    it "shades under the first line only where it has data" do
      days = (Date.new(2026, 9, 1)..Date.new(2026, 9, 3)).to_a
      chart = html(helper.line_chart(days, [ChartsHelper::Series.new(name: "Views", values: [2, 4, nil])], y_title: "Views", label: "Views"))

      expect(chart.css("polygon").map { |area| area["points"] }).to eq(["0.0,120 0.0,60.0 300.0,0.0 300.0,120"])
    end
  end

  describe "#time_chart" do
    it "labels evenly spaced days along the axis, not just the ends" do
      days = (Date.new(2026, 9, 15)..Date.new(2026, 10, 12)).to_a
      axis = html(helper.time_chart(days.map { |day| [day, 1] }, y_title: "Views", label: "Views")).at_css("div.ml-14[aria-hidden]")
      ticks = axis.css("span.absolute").map(&:text).reject(&:empty?)

      expect(ticks).to eq(["15 Sep", "24 Sep", "3 Oct", "12 Oct"])
      expect(axis.css("span.w-px").size).to eq(ticks.size)
    end

    it "spaces the labelled weeks equally, counting back from the latest when the ends can't both be" do
      weeks = (0...12).map { |week| Date.new(2026, 7, 6) + week * 7 }
      axis = html(helper.time_chart(weeks.map { |week| [week, 1] }, y_title: "Views", label: "Views", per: :week)).at_css("div.ml-14[aria-hidden]")
      gaps = axis.css("span.w-px").map { |tick| tick["style"][/[\d.]+/].to_f }.each_cons(2).map { |a, b| (b - a).round(2) }

      expect(axis.css("span.absolute").map(&:text).reject(&:empty?)).to eq(["20 Jul", "10 Aug", "31 Aug", "21 Sep"])
      expect(gaps.uniq).to eq([25.0])
    end

    it "adds the year when the days span two" do
      days = (Date.new(2025, 12, 20)..Date.new(2026, 1, 10)).to_a
      ticks = html(helper.time_chart(days.map { |day| [day, 1] }, y_title: "Views", label: "Views")).css("div[aria-hidden] span.absolute").map(&:text).reject(&:empty?)

      expect(ticks.first).to eq("20 Dec 2025")
      expect(ticks.last).to eq("10 Jan 2026")
    end

    it "reads a week's bar as the week" do
      tip = tips(html(helper.time_chart([[Date.new(2026, 10, 5), 3]], y_title: "Signups", label: "Signups", per: :week))).first

      expect(tip).to eq("title" => "Week of 5 Oct, 2026", "rows" => [{"value" => "3", "color" => "#475569"}])
    end

    it "labels every bucket of a short list of categories" do
      labels = html(helper.time_chart([["1–3", 2], ["4–10", 4]], x_title: "Average position", y_title: "Queries", label: "Positions")).css("div[aria-hidden] span").map(&:text)

      expect(labels).to include("1–3", "4–10")
    end

    it "titles both axes, naming dates by the bucket they stand for" do
      chart = html(helper.time_chart([[Date.new(2026, 10, 5), 3]], y_title: "Signups", label: "Signups", per: :week))

      expect(chart.at_css("span[class*='writing-mode']").text).to eq("Signups")
      expect(chart.css("p").map(&:text)).to include("Week starting")
    end

    it "notes in a readout that a day from the first unsettled one on is still being collected" do
      days = (Date.new(2026, 10, 10)..Date.new(2026, 10, 12)).to_a
      bars = tips(html(helper.time_chart(days.map { |day| [day, 1] }, y_title: "Clicks", label: "Clicks", unsettled: days[1])))
      line = tips(html(helper.time_chart(days.map { |day| [day, 1] }, y_title: "Clicks", label: "Clicks", style: :line, unsettled: days[1])))

      expect(bars.map { |tip| tip["note"] }).to eq([nil, "Data is still being collected", "Data is still being collected"])
      expect(line.map { |tip| tip["note"] }).to eq(bars.map { |tip| tip["note"] })
    end

    it "notes a week as unsettled when any of its days is" do
      weeks = [Date.new(2026, 9, 27), Date.new(2026, 10, 4)]
      tip_notes = tips(html(helper.time_chart(weeks.map { |week| [week, 1] }, y_title: "Clicks", label: "Clicks", per: :week, unsettled: Date.new(2026, 10, 3))))

      expect(tip_notes.map { |tip| tip["note"] }).to eq(["Data is still being collected", "Data is still being collected"])
      expect(tips(html(helper.time_chart(weeks.map { |week| [week, 1] }, y_title: "Clicks", label: "Clicks", per: :week, unsettled: Date.new(2026, 10, 4))))
        .map { |tip| tip["note"] }).to eq([nil, "Data is still being collected"])
    end
  end

  describe "#measures_chart" do
    let(:days) { (Date.new(2026, 8, 1)..Date.new(2026, 8, 4)).to_a }
    let(:measures) do
      [ChartsHelper::Measure.new(name: "Clicks", values: [2, 4, nil, 1], color: "#1f6fd1", whole: true, tick: ->(value) { value.to_s }, reading: ->(value) { "#{value} clicks" }),
       ChartsHelper::Measure.new(name: "Average position", values: [10, 20, nil, 5], color: "#b45c00", dashed: true, inverted: true,
         tick: ->(value) { value.to_s }, reading: ->(value) { value.to_s })]
    end

    it "dots the period compared with in each figure's colour, on its scale, read out after it" do
      compared = [measures.first.dup.tap { |measure| measure.previous = [8, nil, 1, 1]; measure.previous_name = "Clicks, July" }, measures.last]
      chart = html(helper.measures_chart(days, compared, label: "Clicks and position"))

      dotted = chart.css("polyline[data-previous]")
      expect(dotted.map { |line| [line["stroke"], line["stroke-dasharray"]] }).to eq([["#1f6fd1", "0 4"], ["#1f6fd1", "0 4"]])
      expect(chart.css("div[style^='color']").first.css("span:not(.absolute)").map(&:text)).to eq(%w[8.0 4.0 0])
      expect(tips(chart).first["rows"].map { |row| row.slice("value", "name", "dotted") }).to eq([
        {"value" => "2 clicks", "name" => "Clicks"}, {"value" => "8 clicks", "name" => "Clicks, July", "dotted" => true},
        {"value" => "10", "name" => "Average position"}
      ])
    end

    it "puts each figure on its own scale, with an axis titled and labelled in its colour, lower is better upward" do
      chart = html(helper.measures_chart(days, measures, label: "Clicks and position"))
      axes = chart.css("div[style^='color']").map { |axis| [axis["style"], axis.css("span:not(.absolute)").map(&:text)] }

      expect(axes).to eq([["color: #1f6fd1", %w[4.0 2.0 0]], ["color: #b45c00", %w[0 10.0 20.0]]])
      expect(chart.css("span[class*='writing-mode']").map(&:text)).to eq(["Clicks", "Average position"])
      expect(chart.css("polyline").to_h { |line| [line["stroke"], line["stroke-dasharray"]] }).to eq("#1f6fd1" => nil, "#b45c00" => "4 3")
      expect(chart.css("p").map(&:text)).to include("Date")
    end

    it "notes the unsettled days in their readouts, an hour by the day it's in" do
      hours = [Time.utc(2026, 8, 2, 6), Time.utc(2026, 8, 2, 7)].map { |hour| hour.in_time_zone("America/Los_Angeles") }

      expect(tips(html(helper.measures_chart(days, measures, label: "Clicks and position", unsettled: days[3]))).map { |tip| tip["note"] })
        .to eq([nil, nil, nil, "Data is still being collected"])
      expect(tips(html(helper.measures_chart(hours, measures.map { |measure| measure.dup.tap { |copy| copy.values = [1, 2] } },
        label: "Clicks and position", per: :hour, unsettled: Date.new(2026, 8, 2)))).map { |tip| tip["note"] })
        .to eq([nil, "Data is still being collected"])
    end

    it "reads out every figure on a day at the height its own scale puts it" do
      tip = tips(html(helper.measures_chart(days, measures, label: "Clicks and position")))[1]

      expect(tip["rows"]).to eq([
        {"value" => "4 clicks", "name" => "Clicks", "color" => "#1f6fd1", "y" => 0.0},
        {"value" => "20", "name" => "Average position", "color" => "#b45c00", "dashed" => true, "y" => 120.0}
      ])
    end
  end

  describe "#dumbbell_chart" do
    let(:keys) { [["Mobile", "#eb6834", :circle], ["Desktop", "#2a78d6", :square]] }

    it "joins a row's two dots by a line across the gap, on a fixed scale" do
      chart = html(helper.dumbbell_chart([["/slow", [40, 90]]], keys: keys, x_title: "Score", y_title: "Page", label: "Scores"))
      row = chart.at_css("li[data-tip]")

      expect(row.css("span.flex").map { |dot| dot["style"] }).to eq(["left: 40.0%", "left: 90.0%"])
      expect(row.at_css("span.h-0\\.5")["style"]).to eq("left: 40.0%; width: 50.0%")
      expect(JSON.parse(row["data-tip"])["rows"].map { |reading| [reading["name"], reading["value"]] })
        .to eq([["Mobile", "40"], ["Desktop", "90"], ["Gap", "50"]])
    end

    it "draws a lone dot and no line when one reading is missing" do
      row = html(helper.dumbbell_chart([["/new", [nil, 70]]], keys: keys, x_title: "Score", y_title: "Page", label: "Scores")).at_css("li[data-tip]")

      expect(row.css("span.flex").size).to eq(1)
      expect(row.at_css("span.h-0\\.5")).to be_nil
      expect(JSON.parse(row["data-tip"])["rows"].first["value"]).to eq("No data")
    end
  end

  describe "#donut_chart" do
    it "keeps a slice each for the busiest and folds the rest into Other, naming what it holds" do
      counts = {"a" => 50, "b" => 20, "c" => 10, "d" => 10, "e" => 6, "f" => 4, "g" => 0}
      chart = html(helper.donut_chart(counts, label: "Views", unit: "view", empty: "None"))

      expect(chart.css("path").size).to eq(5)
      expect(tips(chart).map { |tip| tip["title"] }).to eq(%w[a b c d Other])
      expect(tips(chart).last["rows"].map { |row| [row["name"], row["value"]] }).to eq([["10 views", "10.0%"], ["e", "6"], ["f", "4"]])
      expect(chart.css("li").map { |row| row.text.squish }.first).to eq("a 50 50.0%")
      expect(chart.text).to include("100")
    end

    it "draws a whole ring for a single slice, and says when there's nothing" do
      expect(html(helper.donut_chart({"mobile" => 3}, label: "Views", unit: "view", empty: "None")).css("circle").size).to eq(1)
      expect(helper.donut_chart({"mobile" => 0}, label: "Views", unit: "view", empty: "No device data.")).to include("No device data.")
    end
  end

  describe "#funnel_chart" do
    it "centres each step at its share of the first, over the step before where it lost some" do
      chart = html(helper.funnel_chart([["Published", 10], ["Indexed", 5], ["Read", 6]], label: "Funnel", unit: "entry"))
      steps = chart.css("li[data-tip]")

      expect(steps.map { |step| step.css("span.bg-slate-600").first["style"] }).to eq(["width: 100.0%", "width: 50.0%", "width: 60.0%"])
      expect(steps[1].at_css("span.bg-slate-200")["style"]).to eq("width: 100.0%")
      expect(steps[2].at_css("span.bg-slate-200")).to be_nil
      expect(JSON.parse(steps[1]["data-tip"])["rows"].map { |row| row["value"] }).to eq(["5", "50%", "−5"])
      expect(steps[1].text.squish).to eq("Indexed 5 −50%")
    end
  end

  describe "#split_bars" do
    it "splits each row's whole by share, leaving out parts with none" do
      chart = html(helper.split_bars([["A post", [1, 3, 0]], ["Quiet", [0, 0, 0]]], parts: [["Clicked", "#2a78d6"], ["Opened", "#eb6834"], ["Bounced", "#eda100"]],
        unit: "mail", label: "Mails", links: {"A post" => "/feed_entries/a"}))
      rows = chart.css("li[data-tip]")

      expect(rows.first.css("div[aria-hidden] span").map { |part| part["style"] }).to eq(["width: 25.0%; background-color: #2a78d6", "width: 75.0%; background-color: #eb6834"])
      expect(rows.first.at_css("a")["href"]).to eq("/feed_entries/a")
      expect(JSON.parse(rows.first["data-tip"])["rows"].map { |row| row["value"] }).to eq(["25.0%", "75.0%", "0.0%"])
      expect(rows.last.text).to include("None yet")
    end
  end

  describe "#scatter_chart" do
    it "places each point by its two figures over a dashed curve, position 1 at the left" do
      points = [ChartsHelper::ScatterPoint.new(x: 1, y: 0.2, color: "#2a78d6", tip: helper.chart_tip("a", [])),
                ChartsHelper::ScatterPoint.new(x: 30, y: 0.05, color: "#eb6834", tip: helper.chart_tip("b", []))]
      chart = html(helper.scatter_chart(points, curve: [[1, 0.2], [30, 0.0]], x_max: 30, x_ticks: [1, 15, 30], y_tick: ->(value) { value.to_s },
        x_title: "Average position", y_title: "CTR", label: "CTR by position", key: [["Usual", "#2a78d6"]]))

      expect(chart.css("span[data-tip]").map { |dot| dot["style"] })
        .to eq(["left: 0.0%; top: 0.0%; background-color: #2a78d6", "left: 100.0%; top: 75.0%; background-color: #eb6834"])
      expect(chart.at_css("polyline")["points"]).to eq("0.0,0.0 600.0,120.0")
      expect(chart.css("div.ml-14 span.absolute.top-1\\.5").map(&:text)).to eq(%w[1 15 30])
      expect(chart.css("ul li").map(&:text)).to eq(["Usual"])
    end
  end

  describe "#ranking_chart" do
    it "measures bars against round gridlines, labelled below" do
      chart = html(helper.ranking_chart([["/", 175, "bg-[#2a78d6]", "#2a78d6"], ["/posts", 90, "bg-[#eb6834]", "#eb6834"]],
        x_title: "Views", y_title: "Page", label: "Views by page", total: 300))

      expect(chart.css("figure > div[aria-hidden] span").map(&:text).reject(&:empty?)).to eq(%w[0 50 100 150 200])
      expect(chart.css("li div.h-5").map { |bar| bar["style"] }).to eq(["width: 87.5%", "width: 45.0%"])
      expect(chart.css("li").first.css("span.bg-slate-200").map { |line| line["style"] })
        .to eq(["left: 25.0%", "left: 50.0%", "left: 75.0%", "left: 100.0%"])
    end

    it "keys each bar's readout with its line's shape" do
      chart = html(helper.ranking_chart([["/", 175, "bg-[#2a78d6]", "#2a78d6", :circle], ["/posts", 90, "bg-[#eb6834]", "#eb6834", :square]],
        x_title: "Views", y_title: "Page", label: "Views by page", total: 300))

      expect(chart.css("li[data-tip]").map { |bar| JSON.parse(bar["data-tip"])["rows"].first["marker"] }).to eq(%w[circle square])
    end
  end
end
