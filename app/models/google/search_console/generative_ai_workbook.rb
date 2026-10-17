# encoding: UTF-8

module Google
  module SearchConsole
    # Search Console's Generative AI report has no API, only an Export
    # button, so its figures come in as the spreadsheet that button makes.
    # Read whole and checked before anything is kept, so a wrong file changes
    # nothing.
    class GenerativeAiWorkbook
      Error = Class.new(StandardError)

      TABS = {
        "Chart" => ["Date", "Impressions"],
        "Pages" => ["Top pages", "Impressions"],
        "Countries" => ["Country", "Impressions"],
        "Devices" => ["Device", "Impressions"]
      }.freeze
      # Filters a whole report is exported under. Any other, such as one page
      # or country picked in Search Console, would make a part read as the
      # whole.
      WHOLE_REPORT_FILTERS = ["Search type", "Date"].freeze
      # What Google calls the report's only search type when the Filters tab
      # leaves it out.
      DEFAULT_SEARCH_TYPE = "Web"

      attr_reader :daily, :pages, :countries, :devices, :search_type

      def initialize(path)
        book = Roo::Excelx.new(path.to_s, file_warning: :ignore)
        missing = TABS.keys - book.sheets
        raise Error, "This isn't a Generative AI performance export: it has no #{missing.to_sentence} #{"tab".pluralize(missing.size)}." if missing.any?

        filters = filters(book)
        others = filters.keys - WHOLE_REPORT_FILTERS
        if others.any?
          raise Error, "This export is filtered by #{others.to_sentence}. Export the report with only a date range and search type, so its figures are the whole site's."
        end

        @search_type = filters["Search type"].presence || DEFAULT_SEARCH_TYPE
        rows = TABS.to_h { |tab, headings| [tab, rows(book.sheet(tab), tab, headings)] }
        @daily = rows["Chart"].to_h { |date, count| [date(date), count] }
        raise Error, "The Chart tab has no days in it." if @daily.empty?

        @pages, @countries, @devices = rows.values_at("Pages", "Countries", "Devices")
      rescue Roo::Error, Zip::Error, ArgumentError, Nokogiri::XML::SyntaxError
        raise Error, "This file couldn't be read as a spreadsheet. Upload the .xlsx file Search Console's Export button makes."
      end

      def from
        daily.keys.min
      end

      def to
        daily.keys.max
      end

      private

      def rows(sheet, tab, headings)
        heading = Array(sheet.row(1)).map { |cell| cell.to_s.strip }
        unless heading.first(2) == headings
          raise Error, "The #{tab} tab should start with #{headings.join(" and ")} columns, but has #{heading.compact_blank.join(" and ").presence || "none"}."
        end

        (2..sheet.last_row.to_i).filter_map do |index|
          label, count = sheet.row(index)
          next if label.blank?

          [label.is_a?(String) ? label.strip : label, count(count, tab, index)]
        end
      end

      # Google writes "~" or "-" where it withholds a small figure, and says
      # they mean zero.
      def count(value, tab, index)
        return 0 if value.blank? || value.to_s.strip.in?(%w[~ -])
        return value.to_i if value.is_a?(Numeric) && value == value.to_i && value >= 0

        Integer(value.to_s.strip.delete(","), 10).tap { |number| raise ArgumentError if number.negative? }
      rescue ArgumentError
        raise Error, "Row #{index} of the #{tab} tab has #{value.inspect} for impressions, which isn't a count."
      end

      # Written as text by Google, though a sheet saved again in a
      # spreadsheet app may hold real dates.
      def date(value)
        value.is_a?(Date) ? value.to_date : Date.iso8601(value.to_s)
      rescue Date::Error
        raise Error, "The Chart tab has #{value.inspect} for a date, which isn't one."
      end

      def filters(book)
        return {} unless book.sheets.include?("Filters")

        sheet = book.sheet("Filters")
        (2..sheet.last_row.to_i).to_h { |index| sheet.row(index).first(2).map { |cell| cell.to_s.strip } }.except("")
      end
    end
  end
end
