# encoding: UTF-8

module Google
  module Analytics
    # Apart from Acquisition, as GA keeps its User reports, so a breakdown
    # is found where it would be in GA.
    class UsersController < ApplicationController
      include DailyReport

      # GA's thresholds drop whole rows rather than rounding them, so the
      # figures here can't be added up to the property's own.
      DEMOGRAPHICS_NOTE = "Only from readers signed in to Google with ad personalisation on, and only once Google signals is on " \
        "(see Settings). GA leaves out any row too small to keep anonymous, so these add up to less than the site's traffic."
      BREAKDOWNS = {
        "countries" => DailyReport::Breakdown.new(key: "countries", label: "Countries", keys: [:country], headings: ["Country"],
          criteria: -> { CountryStat.all },
          search: [Filtering::Contains.new(:country, field: :country, label: "Country code contains", placeholder: "e.g. IN")]),
        "regions" => DailyReport::Breakdown.new(key: "regions", label: "Regions", keys: %i[country region], headings: %w[Country Region],
          criteria: -> { LocationStat.all },
          search: [Filtering::Contains.new(:country, field: :country, label: "Country code contains", placeholder: "e.g. IN"),
            Filtering::Contains.new(:region, field: :region, label: "Region contains", placeholder: "e.g. Maharashtra")]),
        "cities" => DailyReport::Breakdown.new(key: "cities", label: "Cities", keys: %i[country region city], headings: %w[Country Region City],
          criteria: -> { LocationStat.all },
          search: [Filtering::Contains.new(:country, field: :country, label: "Country code contains", placeholder: "e.g. IN"),
            Filtering::Contains.new(:city, field: :city, label: "City contains", placeholder: "e.g. Pune")]),
        "devices" => DailyReport::Breakdown.new(key: "devices", label: "Devices", keys: [:device], headings: ["Device"],
          criteria: -> { DeviceStat.all },
          search: [Filtering::Select.new(:device, field: :device, label: "Device", choices: ["desktop", "mobile", "tablet", "smart tv"])]),
        "technology" => DailyReport::Breakdown.new(key: "technology", label: "Technology", keys: %i[browser operating_system],
          headings: ["Browser", "Operating system"], criteria: -> { TechnologyStat.all },
          search: [Filtering::Contains.new(:browser, field: :browser, label: "Browser contains", placeholder: "e.g. Safari")]),
        "age" => DailyReport::Breakdown.new(key: "age", label: "Age", keys: [:age_bracket], headings: ["Age"],
          criteria: -> { AgeStat.all }, default_sort: {"age_bracket" => "asc"}, note: DEMOGRAPHICS_NOTE),
        "gender" => DailyReport::Breakdown.new(key: "gender", label: "Gender", keys: [:gender], headings: ["Gender"],
          criteria: -> { GenderStat.all }, note: DEMOGRAPHICS_NOTE),
        "languages" => DailyReport::Breakdown.new(key: "languages", label: "Languages", keys: [:language], headings: ["Language"],
          criteria: -> { LanguageStat.all },
          search: [Filtering::Contains.new(:language, field: :language, label: "Language contains", placeholder: "e.g. English")]),
        "screen-resolutions" => DailyReport::Breakdown.new(key: "screen-resolutions", label: "Screen resolution", keys: [:screen_resolution],
          headings: ["Screen resolution"], criteria: -> { ScreenResolutionStat.all },
          search: [Filtering::Contains.new(:screen_resolution, field: :screen_resolution, label: "Resolution contains", placeholder: "e.g. 390x")]),
        # In time order rather than by views, so the busiest hours and days
        # read as a shape across the day and week.
        "time-of-day" => DailyReport::Breakdown.new(key: "time-of-day", label: "Time of day", keys: [:hour], headings: ["Hour"],
          criteria: -> { TimeOfDayStat.all }, default_sort: {"hour" => "asc"}),
        "day-of-week" => DailyReport::Breakdown.new(key: "day-of-week", label: "Day of week", keys: [:day_of_week], headings: ["Day"],
          criteria: -> { TimeOfDayStat.all }, default_sort: {"day_of_week" => "asc"})
      }.freeze
      # The same traffic counts as Acquisition, so a country's figures read
      # against a source's.
      METRICS = AcquisitionController::METRICS
      LIVE_METRICS = AcquisitionController::LIVE_METRICS
      SHOW_SHARES = true
      CHART_METRIC = :views
      EVENT_FILTERING = true
      EXPORT_NAME = "analytics-users"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"

      private

      # Over every reader in the period, whichever breakdown is open, since
      # GA stores new and returning apart from these breakdowns.
      def load_page
        super
        @visitor_weeks = VisitorTypeStat.weekly_views(@period)
      end
    end
  end
end
