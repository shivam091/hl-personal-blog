# encoding: UTF-8

require "rails_helper"

RSpec.describe ExportRequest do
  describe ".record" do
    it "keeps how many rows and bytes the export held" do
      csv = "URL,Title\nhttps://example.com/a,\"Line one\nline two\"\nhttps://example.com/b,B\n"

      request = described_class.record(csv, path: "/sync-requests.csv?status=failed", filename: "sync-requests.csv")

      expect(request).to have_attributes(
        section: "Sync requests", row_count: 2, byte_size: csv.bytesize, trigger: "admin"
      )
    end

    it "counts a header-only export as empty" do
      expect(described_class.record("URL\n", path: "/sync-requests.csv", filename: "x.csv").row_count).to eq(0)
    end
  end

  describe ".section_for" do
    it "names the menu entry the export was taken from" do
      expect(described_class.section_for("/sync-requests.csv?status=failed")).to eq("Sync requests")
      expect(described_class.section_for("/export-requests")).to eq("Export requests")
      expect(described_class.section_for("/sync-requests-old.csv")).to eq("/sync-requests-old")
    end

    it "falls back to the path for a page outside the menu" do
      expect(described_class.section_for("/elsewhere.csv")).to eq("/elsewhere")
    end
  end

  it "shows the search the export was taken with, without paging" do
    request = described_class.new(path: "/sync-requests.csv?status=failed&error=quota&page=3&per_page=50")

    expect(request.filters).to eq("status" => "failed", "error" => "quota")
  end

  it "only re-exports paths inside the admin" do
    expect(described_class.new(path: "/sync-requests.csv").reexport_path).to eq("/sync-requests.csv")
    expect(described_class.new(path: "//evil.example/x.csv").reexport_path).to be_nil
    expect(described_class.new(path: "https://evil.example/x.csv").reexport_path).to be_nil
  end
end
