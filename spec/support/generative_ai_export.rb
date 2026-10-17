# encoding: UTF-8

require "zip"

# Search Console's Generative AI export, written as Google writes it (every
# label a shared string, every count a number) so specs read the same shape the
# upload gets.
module GenerativeAiExport
  DEFAULT_TABS = {
    "Chart" => [["Date", "Impressions"], ["2026-10-01", 3], ["2026-10-02", 5]],
    "Pages" => [["Top pages", "Impressions"], ["https://example.com/post/grid", 6], ["https://example.com/", 4]],
    "Countries" => [["Country", "Impressions"], ["India", 6], ["United States", 2]],
    "Devices" => [["Device", "Impressions"], ["Desktop", 7], ["Mobile", 1]],
    "Filters" => [["Filter", "Value"], ["Search type", "Web (text-based)"], ["Date", "Last 28 days"]]
  }.freeze

  def generative_ai_export(tabs = DEFAULT_TABS)
    strings = []
    index = ->(text) { strings.index(text) || (strings << text).size - 1 }
    sheets = tabs.values.map do |rows|
      cells = rows.each_with_index.map do |row, row_index|
        row.each_with_index.map do |value, column|
          ref = "#{("A".ord + column).chr}#{row_index + 1}"
          value.is_a?(Numeric) ? %(<c r="#{ref}" t="n" s="0"><v>#{value.to_f}</v></c>) : %(<c r="#{ref}" t="s" s="0"><v>#{index.(value.to_s)}</v></c>)
        end.join.then { |row_cells| %(<row r="#{row_index + 1}">#{row_cells}</row>) }
      end
      %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="#{MAIN}"><sheetData>#{cells.join}</sheetData></worksheet>)
    end

    file = Tempfile.new(["generative-ai", ".xlsx"])
    file.close
    Zip::OutputStream.open(file.path) do |zip|
      {
        "[Content_Types].xml" => content_types(sheets.size),
        "_rels/.rels" => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="#{RELS}"><Relationship Id="rId1" Type="#{DOC}/officeDocument" Target="xl/workbook.xml"/></Relationships>),
        "xl/workbook.xml" => %(<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="#{MAIN}" xmlns:r="#{DOC}"><sheets>#{tabs.keys.each_with_index.map { |name, i| %(<sheet name="#{name}" sheetId="#{i + 1}" r:id="rId#{i + 1}"/>) }.join}</sheets></workbook>),
        "xl/_rels/workbook.xml.rels" => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="#{RELS}">#{sheets.each_index.map { |i| %(<Relationship Id="rId#{i + 1}" Type="#{DOC}/worksheet" Target="worksheets/sheet#{i + 1}.xml"/>) }.join}<Relationship Id="rIdS" Type="#{DOC}/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rIdT" Type="#{DOC}/styles" Target="styles.xml"/></Relationships>),
        "xl/styles.xml" => %(<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="#{MAIN}"><numFmts count="0"/><cellXfs count="1"><xf numFmtId="0"/></cellXfs></styleSheet>),
        "xl/sharedStrings.xml" => %(<?xml version="1.0" encoding="UTF-8"?><sst xmlns="#{MAIN}">#{strings.map { |text| "<si><t>#{CGI.escapeHTML(text)}</t></si>" }.join}</sst>),
        **sheets.each_with_index.to_h { |xml, i| ["xl/worksheets/sheet#{i + 1}.xml", xml] }
      }.each do |name, xml|
        zip.put_next_entry(name)
        zip.write(xml)
      end
    end
    # Held for the example, since callers keep only the path and a collected
    # Tempfile deletes its file, sometimes before it's read.
    (@generative_ai_exports ||= []) << file
    file
  end

  def generative_ai_upload(tabs = DEFAULT_TABS, filename: "export.xlsx")
    Rack::Test::UploadedFile.new(generative_ai_export(tabs).path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      original_filename: filename)
  end

  MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  RELS = "http://schemas.openxmlformats.org/package/2006/relationships"
  DOC = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

  private

  def content_types(count)
    overrides = (1..count).map { |i| %(<Override PartName="/xl/worksheets/sheet#{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>) }.join
    %(<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) +
      %(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>) +
      %(<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>) +
      %(<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>) +
      %(<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>#{overrides}</Types>)
  end
end

RSpec.configure do |config|
  config.include GenerativeAiExport
end
