# encoding: UTF-8

module Google
  module Analytics
    # Apart from Acquisition, as GA keeps its User reports, so a breakdown
    # is found where it would be in GA.
    class UsersController < ApplicationController
      include DailyReport
      include VisitorWeeks

      # GA's thresholds drop whole rows rather than rounding them, so the
      # figures here can't be added up to the property's own.
      DEMOGRAPHICS_NOTE = "Only from readers signed in to Google with ad personalisation on, and only once Google signals is on " \
        "(see Settings). GA leaves out any row too small to keep anonymous, so these add up to less than the site's traffic."
      DEVICES = ["desktop", "mobile", "tablet", "smart tv"].freeze
      # Shared by a tab and its splits, so a search means the same in each.
      COUNTRY_SEARCH = Filtering::Contains.new(:country, field: :country, label: "Country code contains", placeholder: "e.g. IN")
      REGION_SEARCH = Filtering::Contains.new(:region, field: :region, label: "Region contains", placeholder: "e.g. Maharashtra")
      CITY_SEARCH = Filtering::Contains.new(:city, field: :city, label: "City contains", placeholder: "e.g. Pune")
      DEVICE_SEARCH = Filtering::Select.new(:device, field: :device, label: "Device", choices: DEVICES)
      BROWSER_SEARCH = Filtering::Contains.new(:browser, field: :browser, label: "Browser contains", placeholder: "e.g. Safari")
      LANGUAGE_SEARCH = Filtering::Contains.new(:language, field: :language, label: "Language contains", placeholder: "e.g. English")
      RESOLUTION_SEARCH = Filtering::Contains.new(:screen_resolution, field: :screen_resolution, label: "Resolution contains", placeholder: "e.g. 390x")
      BREAKDOWNS = {
        "countries" => DailyReport::Breakdown.new(key: "countries", label: "Countries", keys: [:country], headings: ["Country"],
          criteria: -> { CountryStat.all },
          search: [COUNTRY_SEARCH]),
        # Which posts a market reads, which the unsplit tab can't say.
        "country-pages" => DailyReport::Breakdown.new(key: "country-pages", label: "Countries + pages", keys: %i[country page_path],
          headings: ["Country", "Page path"], criteria: -> { CountryStat.all }, parent: "countries", split_label: "By page",
          search: [COUNTRY_SEARCH]),
        # Under Countries, since a region or city is read within its country,
        # and their own tabs would repeat these rows; still at their old
        # paths, so links to them keep working.
        "regions" => DailyReport::Breakdown.new(key: "regions", label: "Regions", keys: %i[country region], headings: %w[Country Region],
          criteria: -> { LocationStat.all }, parent: "countries", split_label: "By region",
          search: [COUNTRY_SEARCH, REGION_SEARCH]),
        "cities" => DailyReport::Breakdown.new(key: "cities", label: "Cities", keys: %i[country region city], headings: %w[Country Region City],
          criteria: -> { LocationStat.all }, parent: "countries", split_label: "By region and city",
          search: [COUNTRY_SEARCH, CITY_SEARCH]),
        "devices" => DailyReport::Breakdown.new(key: "devices", label: "Devices", keys: [:device], headings: ["Device"],
          criteria: -> { DeviceStat.all },
          search: [DEVICE_SEARCH]),
        "device-pages" => DailyReport::Breakdown.new(key: "device-pages", label: "Devices + pages", keys: %i[device page_path],
          headings: ["Device", "Page path"], criteria: -> { DeviceStat.all }, parent: "devices", split_label: "By page",
          search: [DEVICE_SEARCH]),
        "technology" => DailyReport::Breakdown.new(key: "technology", label: "Technology", keys: %i[browser operating_system],
          headings: ["Browser", "Operating system"], criteria: -> { TechnologyStat.all },
          search: [BROWSER_SEARCH]),
        "age" => DailyReport::Breakdown.new(key: "age", label: "Age", keys: [:age_bracket], headings: ["Age"],
          criteria: -> { AgeStat.all }, default_sort: {"age_bracket" => "asc"}, note: DEMOGRAPHICS_NOTE),
        "gender" => DailyReport::Breakdown.new(key: "gender", label: "Gender", keys: [:gender], headings: ["Gender"],
          criteria: -> { GenderStat.all }, note: DEMOGRAPHICS_NOTE),
        "languages" => DailyReport::Breakdown.new(key: "languages", label: "Languages", keys: [:language], headings: ["Language"],
          criteria: -> { LanguageStat.all },
          search: [LANGUAGE_SEARCH]),
        "screen-resolutions" => DailyReport::Breakdown.new(key: "screen-resolutions", label: "Screen resolution", keys: [:screen_resolution],
          headings: ["Screen resolution"], criteria: -> { ScreenResolutionStat.all },
          search: [RESOLUTION_SEARCH]),
        # In time order rather than by views, so the busiest hours and days
        # read as a shape across the day and week.
        "time-of-day" => DailyReport::Breakdown.new(key: "time-of-day", label: "Time of day", keys: [:hour], headings: ["Hour"],
          criteria: -> { TimeOfDayStat.all }, default_sort: {"hour" => "asc"}),
        "day-of-week" => DailyReport::Breakdown.new(key: "day-of-week", label: "Day of week", keys: [:day_of_week], headings: ["Day"],
          criteria: -> { TimeOfDayStat.all }, default_sort: {"day_of_week" => "asc"}),
        # A weekday's own hours, since a Sunday morning and a Monday morning
        # draw different readers.
        "day-of-week-hours" => DailyReport::Breakdown.new(key: "day-of-week-hours", label: "Day of week + hours", keys: %i[day_of_week hour],
          headings: %w[Day Hour], criteria: -> { TimeOfDayStat.all }, parent: "day-of-week", split_label: "By hour",
          default_sort: {"day_of_week" => "asc", "hour" => "asc"})
      }.freeze
      # The same traffic counts as Acquisition, so a country's figures read
      # against a source's.
      HOUR_BREAKDOWNS = %w[time-of-day day-of-week day-of-week-hours].freeze
      METRICS = AcquisitionController::METRICS
      LIVE_METRICS = AcquisitionController::LIVE_METRICS
      SHOW_SHARES = true
      CHART_METRIC = :views
      EVENT_FILTERING = true
      EXPORT_NAME = "analytics-users"
      LIST_LAYOUT = "analytics_users"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"

      private

      def load_page
        super
        load_visitor_weeks
        load_breakdown_charts
      end

      # Every row rather than a page of them, since a share or a pattern is
      # only true of the whole.
      def load_breakdown_charts
        case @breakdown.key
        when "devices"
          @device_sessions = @rows_scope.to_a.to_h { |row| [row[:device].to_s.humanize.presence || "(not set)", row.value(:sessions).to_i] }
        when *HOUR_BREAKDOWNS
          rows = TimeOfDayStat.grouped(@period.apply(TimeOfDayStat.all), by: %i[day_of_week hour])
          @weekly_hours = rows.to_h { |row| [[row[:day_of_week], row[:hour]], row.value(:views).to_i] }
        end
      end
    end
  end
end
