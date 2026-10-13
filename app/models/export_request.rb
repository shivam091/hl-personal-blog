# encoding: UTF-8

require "csv"

# Exports carry the blog's data out of the admin, so each one is kept on
# record. The path is the export's own URL, so the same export can be taken
# again with today's data.
class ExportRequest
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  TRIGGERS = {"admin" => "Admin", "rake" => "Rake task"}.freeze
  # Paging changes the list on screen, never what's exported.
  IGNORED_PARAMS = %w[page per_page format].freeze

  field :section, type: String
  field :detail, type: String
  field :path, type: String
  field :filename, type: String
  field :row_count, type: Integer
  field :byte_size, type: Integer
  field :trigger, type: String, default: "admin"

  # Sorts carry an _id tiebreaker, which an index without it can't serve.
  index({created_at: -1, _id: 1})
  index({section: 1})

  validates :section, :path, :filename, presence: true
  validates :trigger, inclusion: {in: TRIGGERS.keys}

  class << self
    def record(data, path:, filename:, **attributes)
      create!(
        section: section_for(path),
        path: path,
        filename: filename,
        row_count: [CSV.new(data).count - 1, 0].max,
        byte_size: data.bytesize,
        **attributes
      )
    end

    # Named after the menu entry the export was taken from, so the record
    # reads as the admin knows the page.
    def section_for(path)
      helpers = Rails.application.routes.url_helpers
      link = NavigationHelper.flat_entries.map do |entry|
        [entry[:label], helpers.public_send(:"#{entry[:route]}_path")]
      end.reject { |_label, prefix| prefix == "/" }
         .select { |_label, prefix| path.match?(%r{\A#{Regexp.escape(prefix)}(?=[/.?]|\z)}) }
         .max_by { |_label, prefix| prefix.length }
      link ? link.first : path.split(/[.?]/).first
    end
  end

  def filters
    query = path.to_s.split("?", 2).second
    Rack::Utils.parse_query(query.to_s).except(*IGNORED_PARAMS)
  end

  # Stored paths come from the app's own routes, but a protocol-relative
  # one would leave the admin.
  def reexport_path
    path if path.to_s.start_with?("/") && !path.start_with?("//")
  end

  def trigger_label
    TRIGGERS.fetch(trigger, trigger)
  end

  def to_s
    "#{section} export"
  end
end
