# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::GenerativeAiWorkbook do
  def workbook(tabs = GenerativeAiExport::DEFAULT_TABS)
    described_class.new(generative_ai_export(tabs).path)
  end

  def with(tab, rows)
    GenerativeAiExport::DEFAULT_TABS.merge(tab => rows)
  end

  it "reads each tab Search Console exports, with the days it covers and its search type" do
    book = workbook

    expect(book.daily).to eq(Date.new(2026, 10, 1) => 3, Date.new(2026, 10, 2) => 5)
    expect([book.from, book.to, book.search_type]).to eq([Date.new(2026, 10, 1), Date.new(2026, 10, 2), "Web (text-based)"])
    expect(book.pages).to eq([["https://example.com/post/grid", 6], ["https://example.com/", 4]])
    expect(book.countries).to eq([["India", 6], ["United States", 2]])
    expect(book.devices).to eq([["Desktop", 7], ["Mobile", 1]])
  end

  it "reads Google's withheld figures as zero and skips blank rows" do
    book = workbook(with("Chart", [["Date", "Impressions"], ["2026-10-01", "~"], ["2026-10-02", "-"], ["", ""], ["2026-10-03", "1,204"]]))

    expect(book.daily.values).to eq([0, 0, 1204])
  end

  it "takes the search type as Web when there's no Filters tab" do
    expect(workbook(GenerativeAiExport::DEFAULT_TABS.except("Filters")).search_type).to eq("Web")
  end

  it "turns away a file that isn't the export, naming what's wrong" do
    expect { workbook(GenerativeAiExport::DEFAULT_TABS.except("Pages", "Devices")) }
      .to raise_error(described_class::Error, /no Pages and Devices tabs/)
    expect { workbook(with("Countries", [["Region", "Clicks"]])) }
      .to raise_error(described_class::Error, /Countries tab should start with Country and Impressions columns, but has Region and Clicks/)
    expect { workbook(with("Chart", [["Date", "Impressions"]])) }.to raise_error(described_class::Error, /no days/)
    expect { workbook(with("Chart", [["Date", "Impressions"], ["yesterday", 1]])) }.to raise_error(described_class::Error, /"yesterday" for a date/)
    expect { workbook(with("Pages", [["Top pages", "Impressions"], ["/", "lots"]])) }.to raise_error(described_class::Error, /Row 2 of the Pages tab/)
    expect { workbook(with("Pages", [["Top pages", "Impressions"], ["/", -3]])) }.to raise_error(described_class::Error, /Row 2 of the Pages tab/)
  end

  it "turns away an export filtered to part of the site, since its figures aren't the whole site's" do
    filtered = with("Filters", [["Filter", "Value"], ["Search type", "Web (text-based)"], ["Country", "India"], ["Date", "Last 28 days"]])

    expect { workbook(filtered) }.to raise_error(described_class::Error, /filtered by Country/)
  end

  it "turns away a file that isn't a spreadsheet at all" do
    file = Tempfile.new(["notes", ".xlsx"]).tap { |notes| notes.write("just text") && notes.close }

    expect { described_class.new(file.path) }.to raise_error(described_class::Error, /couldn't be read as a spreadsheet/)
  end
end
