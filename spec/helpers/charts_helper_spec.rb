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
      map = html(helper.world_map({"IN" => 1000, "US" => 10, "SG" => 4, "XX" => 3, "ZZ" => 7}, label: "Views by country", unit: "view"))
      india = map.css("path").find { |path| JSON.parse(path["data-tip"])["title"] == "🇮🇳 India" }
      brazil = map.css("path").find { |path| JSON.parse(path["data-tip"])["title"] == "🇧🇷 Brazil" }

      expect(india["class"]).to include("fill-[#0d366b]")
      expect(JSON.parse(india["data-tip"])["rows"]).to eq([{"value" => "1,000", "name" => "Views"}])
      expect(brazil["class"]).to include("fill-[#f0efec]")
      singapore = map.css("path").find { |path| JSON.parse(path["data-tip"])["title"].include?("Singapore") }
      expect(singapore["class"]).not_to include("fill-[#f0efec]")
      expect(map.at_css("figcaption").text).to include("XX 3")
      expect(map.at_css("figcaption").text).not_to include("SG")
      expect(map.at_css("figcaption").text).not_to include("ZZ")
    end
  end

  describe "#world_map coverage" do
    it "draws every country the app knows, Antarctica included" do
      known = YAML.load_file(Rails.root.join("config/countries.yml")).values

      expect(known - WorldMap.codes.to_a).to be_empty
      expect(WorldMap.height).to be >= WorldMap.countries.find { |country| country.code == "AQ" }.path.scan(/ (\d+\.?\d*)/).flatten.map(&:to_f).max
    end
  end

  describe "#world_map islands" do
    it "draws the outlying islands of a country as part of its shape" do
      india = WorldMap.countries.find { |country| country.code == "IN" }

      expect(india.path.scan("M").size).to be > 10
    end
  end

  describe "#world_map also" do
    it "reads other figures in each country's tooltip beside the one that shades the map, then each one's earlier figure" do
      map = html(helper.world_map({"IN" => 50}, label: "Impressions by country", unit: "impression", previous: {"IN" => 10}, previous_name: "Previous period",
        also: [["Clicks", {"IN" => 2}, {"IN" => 1}], ["Likes", {"IN" => 3}, nil]]))
      india = JSON.parse(map.css("path").find { |path| JSON.parse(path["data-tip"])["title"].include?("India") }["data-tip"])

      expect(india["rows"].map { |row| [row["name"], row["value"]] }).to eq([["Impressions", "50"], ["Clicks", "2"], ["Likes", "3"], ["Impressions", "10"], ["Clicks", "1"]])
      expect(india["rows"].find { |row| row["name"] == "Clicks" }["change"]).to eq("(+100%)")
    end
  end

  describe "#world_map details" do
    it "reads a country's own figures, and a country without any as the figures given for the rest" do
      details = Hash.new([["Likes", 0]]).merge("IN" => [["Likes", 4]])
      map = html(helper.world_map({"IN" => 50}, label: "Views by country", unit: "view", details: details))
      likes = ->(title) { JSON.parse(map.css("path").find { |path| JSON.parse(path["data-tip"])["title"].include?(title) }["data-tip"])["rows"].map { |row| [row["name"], row["value"]] } }

      expect(likes.("India")).to eq([["Views", "50"], ["Likes", "4"]])
      expect(likes.("China")).to eq([["Views", "0"], ["Likes", "0"]])
    end
  end

  describe "#world_map reveal" do
    it "fades countries in from the busiest down to the empty ones, on the scale the fill uses" do
      map = html(helper.world_map({"IN" => 1000, "US" => 10, "SG" => 1}, label: "Views by country", unit: "view"))
      delay = ->(title) { map.css("path").find { |node| JSON.parse(node["data-tip"])["title"].include?(title) }["style"][/animation-delay: (\d+)ms/, 1].to_i }

      expect(delay.("India")).to eq(0)
      expect(delay.("United States")).to be_between(1, delay.("Singapore") - 1)
      expect(delay.("Singapore")).to be < delay.("Brazil")
      expect(delay.("Brazil")).to eq(ChartsHelper::MAP_REVEAL_MS)
    end

    it "shows every country at once when there are no counts" do
      map = html(helper.world_map({}, label: "Views by country", unit: "view"))

      expect(map.css("path").map { |node| node["style"] }.uniq).to eq(["animation-delay: 0ms"])
    end
  end

  describe "#world_map compared" do
    it "outlines countries that rose or fell and reads each against the period compared with" do
      map = html(helper.world_map({"IN" => 10, "US" => 2, "BR" => 5}, label: "Views by country", unit: "view",
        previous: {"IN" => 5, "US" => 4, "BR" => 5}, previous_name: "Previous period"))
      path = ->(title) { map.css("path").find { |node| JSON.parse(node["data-tip"])["title"] == title } }

      expect(path.("🇮🇳 India")["class"]).to include("stroke-emerald-600")
      expect(path.("🇺🇸 United States")["class"]).to include("stroke-red-600")
      expect(path.("🇧🇷 Brazil")["class"]).to include("stroke-white")
      expect(JSON.parse(path.("🇮🇳 India")["data-tip"])["rows"].map { |row| row.slice("name", "period", "value", "change") }).to eq([{"name" => "Views", "value" => "10", "change" => "(+100%)"}, {"name" => "Views", "period" => "Previous period", "value" => "5"}])
      expect(map.text).to include("Up on the period compared with")
    end

    it "draws nothing extra without a period compared with" do
      map = html(helper.world_map({"IN" => 10}, label: "Views by country", unit: "view"))

      expect(map.css("path[class*=stroke-emerald-600], path[class*=stroke-red-600]")).to be_empty
      expect(map.text).not_to include("Up on the period")
    end
  end

  describe "#time_chart compared" do
    it "adds the previous value to each bar's readout and a dotted line, on a scale that holds both" do
      days = (Date.new(2026, 10, 10)..Date.new(2026, 10, 11)).to_a
      chart = html(helper.time_chart(days.map { |day| [day, 1] }, y_title: "Requests", label: "Requests", previous: [4, nil], previous_name: "Previous period"))

      expect(tips(chart).map { |tip| tip["title"] }).to eq(["Day 1", "Day 2"])
      expect(tips(chart).map { |tip| tip["rows"] }).to eq([
        [{"value" => "1", "name" => "Requests", "period" => "Sat, 10 Oct 2026", "color" => ChartsHelper::BAR_COLOR, "change" => "(−75%)", "tone" => -1},
         {"value" => "4", "name" => "Requests", "period" => "Previous period", "color" => ChartsHelper::BAR_COLOR, "dotted" => true, "earlier" => true}],
        [{"value" => "1", "name" => "Requests", "period" => "Sun, 11 Oct 2026", "color" => ChartsHelper::BAR_COLOR},
         {"value" => "No data", "name" => "Requests", "period" => "Previous period", "color" => ChartsHelper::BAR_COLOR, "dotted" => true, "earlier" => true}]
      ])
      expect(chart.css("polyline[data-previous]")).to be_present
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

      expect(tip["title"]).to eq("Mon, 5 Oct, 2026")
      expect(tip["rows"].map { |row| [row["value"], row["name"], row["color"]] }).to eq([
        ["60.0% · 6", "🇮🇳 IN", "#2a78d6"], ["20.0% · 2", "🇺🇸 US", "#eb6834"], ["20.0% · 2", "Other", "#a8a7a1"]
      ])
    end

    it "says so when there's nothing to split" do
      expect(helper.share_chart({keys: [], unit: :week, buckets: {}}, y_title: "Share of views", label: "Shares")).to include("No views in this period.")
    end
  end

  describe "chart tools and drill-downs" do
    let(:days) { (Date.new(2026, 8, 1)..Date.new(2026, 8, 3)).to_a }

    it "gives a daily line chart days to zoom to and a wash under its line" do
      assign(:period, Object.new)
      chart = html(helper.line_chart(days, [ChartsHelper::Series.new(name: "Views", values: [1, 2, 3])], label: "Views", y_title: "Views"))

      expect(tips(chart).map { |tip| tip["key"] }).to eq(%w[2026-08-01 2026-08-02 2026-08-03])
      expect(chart.css("button")).to be_empty
      expect(chart.at_css("linearGradient#area-fade")).not_to be_nil
      expect(chart.at_css("polygon")["fill"]).to eq("url(#area-fade)")
    end

    it "offers no zoom on weeks, since a bucket's end isn't known" do
      chart = html(helper.line_chart(days, [ChartsHelper::Series.new(name: "Views", values: [1, 2, 3])], label: "Views", y_title: "Views", per: :week))

      expect(tips(chart).map { |tip| tip["key"] }).to all(be_nil)
    end

    it "links a country to where it goes and lets a map be zoomed" do
      map = html(helper.world_map({"IN" => 5}, label: "Views", unit: "view", links: {"IN" => "/somewhere"}))

      expect(tips(map).find { |tip| tip["title"].include?("India") }["href"]).to eq("/somewhere")
      expect(map.css("button").map { |button| button["aria-label"] }).to eq(["Zoom in", "Zoom out"])
      expect(map.at_css("[data-controller=map-zoom]")["data-action"]).to include("map-zoom#wheel")
    end
  end

  describe "#line_chart" do
    it "starts on the first day with data, marking where each line starts and ends, skipping days without data, and a line of one point once" do
      days = (Date.new(2026, 9, 1)..Date.new(2026, 9, 4)).to_a
      chart = html(helper.line_chart(days, [
        ChartsHelper::Series.new(name: "Total", values: [nil, 10, 20, 5], dotted: true),
        ChartsHelper::Series.new(name: "scroll", values: [nil, nil, 8, nil], color: "#2a78d6")
      ], y_title: "Events", label: "Events per day"))

      expect(chart.css("span[data-series]").map { |marker| [marker["data-series"], marker["style"][/left: [\d.]+%; top: [\d.]+%/]] })
        .to eq([["0", "left: 0.0%; top: 50.0%"], ["0", "left: 100.0%; top: 75.0%"], ["1", "left: 50.0%; top: 60.0%"]])
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
        ChartsHelper::Series.new(name: "This period", values: Array.new(28) { |i| i + 1 }),
        ChartsHelper::Series.new(name: "Period before", values: [nil] * 28, dashed: true)
      ], y_title: "Views", label: "Views"))
      tip = tips(chart)[27]

      expect(tips(chart).size).to eq(28)
      expect(tip["title"]).to eq("Day 28")
      expect(tip["rows"]).to eq([
        {"value" => "28", "name" => "This period", "period" => "Mon, 28 Sep 2026", "color" => "#1e293b", "y" => 0.0},
        {"value" => "No data", "name" => "Period before", "period" => "Mon, 28 Sep 2026", "color" => "#94a3b8", "dashed" => true}
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
      expect(tips(chart).last["rows"].last).to eq("value" => "A post", "name" => "Published", "color" => "#eb6834", "marker" => "triangle")
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
    it "shows the crosshair cursor only where a drag can zoom to the days" do
      days = [[Date.new(2026, 10, 1), 1], [Date.new(2026, 10, 2), 2]]
      chart = -> { html(helper.time_chart(days, y_title: "Views", label: "Views", **_1)) }

      expect(chart.({}).at_css(".cursor-crosshair")).to be_nil
      assign(:period, Object.new)
      expect(chart.({}).at_css(".cursor-crosshair")).to be_present
      expect(chart.(zoom: false).at_css(".cursor-crosshair")).to be_nil
      expect(chart.(per: :week).at_css(".cursor-crosshair")).to be_nil
    end

    it "labels evenly spaced days along the axis, not just the ends" do
      days = (Date.new(2026, 9, 15)..Date.new(2026, 10, 12)).to_a
      axis = html(helper.time_chart(days.map { |day| [day, 1] }, y_title: "Views", label: "Views")).at_css("div.ml-14[aria-hidden]")
      ticks = axis.css("span.absolute").map(&:text).reject(&:empty?)

      expect(ticks).to eq(["15 Sep", "24 Sep", "3 Oct", "12 Oct"])
      expect(axis.css("span.w-px").size).to eq(ticks.size)
    end

    it "spaces the labelled weeks equally back from the latest when the ends can't both be, still labelling the first" do
      weeks = (0...12).map { |week| Date.new(2026, 7, 6) + week * 7 }
      axis = html(helper.time_chart(weeks.map { |week| [week, 1] }, y_title: "Views", label: "Views", per: :week)).at_css("div.ml-14[aria-hidden]")
      gaps = axis.css("span.w-px").map { |tick| tick["style"][/[\d.]+/].to_f }.each_cons(2).map { |a, b| (b - a).round(2) }

      expect(axis.css("span.absolute").map(&:text).reject(&:empty?)).to eq(["6 Jul", "20 Jul", "10 Aug", "31 Aug", "21 Sep"])
      expect(gaps.drop(1).uniq).to eq([25.0])
    end

    it "labels the first day whatever the period's length, without one crowding it" do
      (2..400).each do |size|
        ticks = helper.send(:tick_indexes, size)
        shortest = ((size - 1) / (ChartsHelper::MAX_TICKS - 1.0)).ceil

        expect(ticks.first).to eq(0), "#{size} days"
        expect(ticks.last).to eq(size - 1), "#{size} days"
        expect(ticks.each_cons(2).map { |a, b| b - a }.min).to be >= shortest / 2.0, "#{size} days" if ticks.size > 1
      end
    end

    it "adds the year when the days span two" do
      days = (Date.new(2025, 12, 20)..Date.new(2026, 1, 10)).to_a
      ticks = html(helper.time_chart(days.map { |day| [day, 1] }, y_title: "Views", label: "Views")).css("div[aria-hidden] span.absolute").map(&:text).reject(&:empty?)

      expect(ticks.first).to eq("20 Dec 2025")
      expect(ticks.last).to eq("10 Jan 2026")
    end

    it "reads a week's bar as the week" do
      tip = tips(html(helper.time_chart([[Date.new(2026, 10, 5), 3]], y_title: "Signups", label: "Signups", per: :week))).first

      expect(tip).to eq("title" => "Week 1", "rows" => [{"value" => "3", "name" => "Signups", "period" => "Mon, 5 Oct 2026", "color" => "#475569"}])
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
      expect(tips(chart).first["rows"].map { |row| row.slice("value", "name", "period", "dotted") }).to eq([
        {"value" => "2 clicks", "name" => "Clicks", "period" => "Sat, 1 Aug 2026"}, {"value" => "10", "name" => "Average position", "period" => "Sat, 1 Aug 2026"},
        {"value" => "8 clicks", "name" => "Clicks", "period" => "Clicks, July", "dotted" => true}
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
        {"value" => "4 clicks", "name" => "Clicks", "period" => "Sun, 2 Aug 2026", "color" => "#1f6fd1", "y" => 0.0},
        {"value" => "20", "name" => "Average position", "period" => "Sun, 2 Aug 2026", "color" => "#b45c00", "dashed" => true, "y" => 120.0}
      ])
    end
  end

  describe "#dumbbell_chart" do
    let(:keys) { [["Mobile", "#eb6834", :circle], ["Desktop", "#2a78d6", :square]] }

    it "joins a row's two dots by a line across the gap, on a fixed scale" do
      chart = html(helper.dumbbell_chart([["/slow", [40, 90]]], keys: keys, x_title: "Score", y_title: "Page", label: "Scores"))
      row = chart.at_css("li div[data-tip]")

      expect(row.css("span.flex").map { |dot| dot["style"] }).to eq(["left: 40.0%", "left: 90.0%"])
      expect(row.at_css("span.h-0\\.5")["style"]).to eq("left: 40.0%; width: 50.0%")
      expect(JSON.parse(row["data-tip"])["rows"].map { |reading| [reading["name"], reading["value"]] })
        .to eq([["Mobile", "40"], ["Desktop", "90"], ["Gap", "50"]])
    end

    it "draws a lone dot and no line when one reading is missing" do
      row = html(helper.dumbbell_chart([["/new", [nil, 70]]], keys: keys, x_title: "Score", y_title: "Page", label: "Scores")).at_css("li div[data-tip]")

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
      expect(tips(chart).last["rows"].map { |row| [row["name"], row["value"]] }).to eq([["Views", "10"], ["Share", "10.0%"], ["e", "6"], ["f", "4"]])
      expect(chart.css("li").map { |row| row.text.squish }.first).to eq("a 50 50.0%")
      expect(chart.text).to include("100")
    end

    it "draws a whole ring for a single slice, and says when there's nothing" do
      expect(html(helper.donut_chart({"mobile" => 3}, label: "Views", unit: "view", empty: "None")).css("circle").size).to eq(1)
      expect(helper.donut_chart({"mobile" => 0}, label: "Views", unit: "view", empty: "No device data.")).to include("No device data.")
    end
  end

  describe "tooltip hits" do
    it "puts a ranking row's readout on its bar, not on its name" do
      chart = html(helper.ranking_chart([["/", 175, "bg-[#2a78d6]", "#2a78d6"]], x_title: "Views", y_title: "Page", label: "Views by page", total: 175))

      expect(chart.css("li [data-tip]").size).to eq(1)
      expect(chart.at_css("li [data-tip]").at_css("div.h-5")).not_to be_nil
      expect(chart.css("li > span [data-tip], li > span[data-tip], li[data-tip]")).to be_empty
    end

    it "puts a funnel step's readout on its bar, not on its name" do
      chart = html(helper.funnel_chart([["Published", 10], ["Indexed", 5]], label: "Funnel", unit: "entry"))

      expect(chart.css("li[data-tip]")).to be_empty
      expect(chart.css("li [data-tip]").size).to eq(2)
      expect(chart.at_css("li [data-tip]").at_css("span.bg-slate-600")).not_to be_nil
    end
  end

  describe "#line_chart dates on a phone" do
    it "keeps the first and the last date of whatever dates the chart labels" do
      (4..40).each do |size|
        dates = (Date.new(2026, 1, 1)...(Date.new(2026, 1, 1) + size)).to_a
        chart = html(helper.line_chart(dates, [ChartsHelper::Series.new(name: "Views", values: Array.new(size, 1))], label: "Views", y_title: "Views"))
        shown = chart.css("div.border-t span").reject { |label| label["class"].to_s.include?("max-sm:hidden") }.map { |label| label.text.strip }.reject(&:empty?)

        expect(shown.first).to eq(I18n.l(dates.first, format: "%-d %b"))
        expect(shown.last).to eq(I18n.l(dates.last, format: "%-d %b"))
      end
    end
  end

  describe "#funnel_chart" do
    it "centres each step at its share of the first, over a full-width track every step shares" do
      chart = html(helper.funnel_chart([["Published", 10], ["Indexed", 5], ["Read", 6]], label: "Funnel", unit: "entry"))
      steps = chart.css("li")

      expect(steps.map { |step| step.css("span.bg-slate-600").first["style"] }).to eq(["width: 100.0%", "width: 50.0%", "width: 60.0%"])
      expect(steps.map { |step| step.at_css("span.bg-slate-200.inset-0") }).to all(be_present)
      expect(JSON.parse(steps[1].at_css("[data-tip]")["data-tip"])["rows"].map { |row| row["value"] }).to eq(["5", "50%", "−5"])
      expect(steps[1].text.squish).to eq("Indexed 5 −50%")
    end
  end

  describe "#reading_unit" do
    it "keeps a symbol or short unit and drops a word for what is counted" do
      expect(%w[% ms MB s].map { |unit| helper.send(:reading_unit, " #{unit}") }).to eq([" %", " ms", " MB", " s"])
      expect([" requests", " views", nil].map { |unit| helper.send(:reading_unit, unit) }).to eq(["", "", ""])
    end

    it "keeps it off a bar's reading" do
      tip = tips(html(helper.time_chart([[Date.new(2026, 10, 5), 3]], y_title: "Signups", label: "Signups", unit: " signups"))).first

      expect(tip["rows"].first["value"]).to eq("3")
    end
  end

  describe "#metric_name" do
    it "names an earlier period's line for the current one it is against, not for its own dated name" do
      median = ChartsHelper::Series.new(name: "Median", values: [1, 2])
      p95 = ChartsHelper::Series.new(name: "95th percentile", values: [3, 4])
      before = ChartsHelper::Series.new(name: "Median, 1 Sep – 7 Sep", values: [1, 1], dotted: true, against: median)
      series = [median, p95, before, ChartsHelper::Series.new(name: "95th percentile, 1 Sep – 7 Sep", values: [2, 2], dotted: true, against: p95)]

      expect(helper.send(:metric_name, series, before, "Ms")).to eq("Median")
    end
  end

  describe "#share_bar" do
    it "reads each part out on hover and leaves an empty part off" do
      html = helper.share_bar([["Good", 0.75, "#10b981", [{value: "75%", name: "Good"}]], ["Poor", 0.0, "#ef4444", []]], label: "Ratings")

      tips = Nokogiri::HTML.fragment(html).css("[data-tip]").map { |part| JSON.parse(part["data-tip"]) }
      expect(tips.map { |tip| tip["title"] }).to eq(["Good"])
    end
  end

  describe "#heat_cell" do
    it "shades by value and carries its readout" do
      html = helper.heat_cell("3", 3, 3, tip: helper.chart_tip("Mon", [{value: "3", name: "Requests"}]))

      cell = Nokogiri::HTML.fragment(html).at_css("div")
      expect(JSON.parse(cell["data-tip"])["title"]).to eq("Mon")
      expect(cell["class"]).to include(ChartsHelper::HEAT_CLASSES.last)
    end
  end

  describe "#split_bars" do
    it "splits each row's whole by share, leaving out parts with none" do
      chart = html(helper.split_bars([["A post", [1, 3, 0]], ["Quiet", [0, 0, 0]]], parts: [["Clicked", "#2a78d6"], ["Opened", "#eb6834"], ["Bounced", "#eda100"]],
        unit: "mail", label: "Mails", links: {"A post" => "/feed_entries/a"}))
      rows = chart.css("ul.grid > li")

      expect(rows.map { |row| row.at_css("a, span.truncate")["data-tip"] }).to all(be_nil)
      expect(rows.first.css("div[aria-hidden] span").map { |part| part["style"] }).to eq(["width: 25.0%; background-color: #2a78d6", "width: 75.0%; background-color: #eb6834"])
      expect(rows.first.at_css("a")["href"]).to eq("/feed_entries/a")
      expect(JSON.parse(rows.first.at_css("div[data-tip]")["data-tip"])["rows"].map { |row| row["value"] }).to eq(["25.0% · 1", "75.0% · 3", "0.0% · 0"])
      expect(rows.last.text).to include("None yet")
    end
  end

  describe "#sparkline" do
    it "draws from zero to the highest value" do
      chart = html(helper.sparkline([0, 5, 10], label: "Views by day"))

      expect(chart.at_css("polyline")["points"]).to eq("0.0,22.0 40.0,12.0 80.0,2.0")
    end

    it "breaks the line at a missing value and reaches below zero" do
      chart = html(helper.sparkline([-10, 10, nil, 0, 10], label: "Gap by week"))

      expect(chart.css("polyline").map { |line| line["points"] }).to eq(["0.0,22.0 20.0,2.0", "60.0,12.0 80.0,2.0"])
      expect(chart.css("line").last.to_h.values_at("x1", "y1")).to eq(%w[80.0 2.0])
    end

    it "has nothing to draw when every value is missing" do
      expect(helper.sparkline([nil, nil], label: "Gap by week")).to include("—")
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

    it "reaches below zero when asked, with level lines across" do
      points = [ChartsHelper::ScatterPoint.new(x: 1, y: -0.5, color: "#2a78d6", tip: helper.chart_tip("a", []))]
      chart = html(helper.scatter_chart(points, x_max: 2, x_ticks: [1, 2], y_tick: ->(value) { value.to_s }, y_min: -1.0, y_max: 1.0,
        lines: [{y: 0.0, color: "#1e293b"}, {y: 0.5, color: "#eda100", dashed: true}], x_title: "Views", y_title: "Gap", label: "Gap by views"))

      expect(chart.at_css("span[data-tip]")["style"]).to include("top: 75.0%")
      expect(chart.css("svg line[stroke='#1e293b'], svg line[stroke='#eda100']").map { |line| [line["y1"], line["stroke-dasharray"]] })
        .to eq([["60.0", nil], ["30.0", "4 3"]])
      expect(chart.css("div.h-56 > span").map(&:text).reject(&:empty?)).to include("1.0", "0.0", "-1.0")
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

      expect(chart.css("li [data-tip]").map { |bar| JSON.parse(bar["data-tip"])["rows"].first["marker"] }).to eq(%w[circle square])
    end
  end

  describe "#stacked_chart" do
    let(:days) { (Date.new(2026, 9, 1)..Date.new(2026, 9, 2)).to_a }

    it "leaves a part below zero and one not recorded undrawn, but reads out their figures and the parts added up" do
      chart = html(helper.stacked_chart(days, [
        ChartsHelper::Series.new(name: "Found", values: [10, 30], color: "#2a78d6"),
        ChartsHelper::Series.new(name: "Later", values: [nil, 5], color: "#eb6834"),
        ChartsHelper::Series.new(name: "Left", values: [5, -15], color: "#a8a7a1")
      ], y_title: "Views", label: "Views", total_name: "Gap"))

      expect(chart.css("rect[fill^='#']").map { |bar| bar["fill"] }).to eq(%w[#2a78d6 #a8a7a1 #2a78d6 #eb6834])
      first, second = tips(chart).map { |tip| tip["rows"].to_h { |row| [row["name"], row["value"]] } }
      expect(first).to eq("Found" => "10", "Later" => "No data", "Left" => "5", "Gap" => "15")
      expect(second).to include("Left" => "-15", "Gap" => "20")
    end

    it "sets each bar's total against the earlier one, but gives no change from a total below zero" do
      chart = html(helper.stacked_chart(days, [ChartsHelper::Series.new(name: "Found", values: [10, 30], color: "#2a78d6")],
        y_title: "Views", label: "Views", total_name: "Gap", previous: [5, -2], previous_name: "Before"))

      changes = tips(chart).map { |tip| tip["rows"].find { |row| row["name"] == "Gap" && !row["earlier"] }["change"] }
      expect(changes).to eq(["(+100%)", nil])
    end
  end
end
