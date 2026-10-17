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
        # Which posts a market reads, and what it reads on, which the
        # unsplit tab can't say.
        "country-pages" => DailyReport::Breakdown.new(key: "country-pages", label: "Countries + pages", keys: %i[country page_path],
          headings: ["Country", "Page path"], criteria: -> { CountryStat.all }, parent: "countries", split_label: "By page",
          search: [COUNTRY_SEARCH]),
        "country-devices" => DailyReport::Breakdown.new(key: "country-devices", label: "Countries + devices", keys: %i[country device],
          headings: %w[Country Device], criteria: -> { CountryDeviceStat.all }, parent: "countries", split_label: "By device",
          search: [COUNTRY_SEARCH, DEVICE_SEARCH]),
        # Under Countries, since a region or city is read within its country,
        # and their own tabs would repeat these rows; still at their old
        # paths, so links to them keep working.
        "regions" => DailyReport::Breakdown.new(key: "regions", label: "Regions", keys: %i[country region], headings: %w[Country Region],
          criteria: -> { LocationStat.all }, parent: "countries", split_label: "By region",
          search: [COUNTRY_SEARCH, REGION_SEARCH]),
        "region-pages" => DailyReport::Breakdown.new(key: "region-pages", label: "Regions + pages", keys: %i[country region page_path],
          headings: ["Country", "Region", "Page path"], criteria: -> { LocationStat.all }, parent: "countries", split_label: "By region and page",
          search: [COUNTRY_SEARCH, REGION_SEARCH]),
        "cities" => DailyReport::Breakdown.new(key: "cities", label: "Cities", keys: %i[country region city], headings: %w[Country Region City],
          criteria: -> { LocationStat.all }, parent: "countries", split_label: "By region and city",
          search: [COUNTRY_SEARCH, CITY_SEARCH]),
        "city-pages" => DailyReport::Breakdown.new(key: "city-pages", label: "Cities + pages", keys: %i[country region city page_path],
          headings: ["Country", "Region", "City", "Page path"], criteria: -> { LocationStat.all }, parent: "countries", split_label: "By region, city and page",
          search: [COUNTRY_SEARCH, CITY_SEARCH]),
        "devices" => DailyReport::Breakdown.new(key: "devices", label: "Devices", keys: [:device], headings: ["Device"],
          criteria: -> { DeviceStat.all },
          search: [DEVICE_SEARCH]),
        "device-pages" => DailyReport::Breakdown.new(key: "device-pages", label: "Devices + pages", keys: %i[device page_path],
          headings: ["Device", "Page path"], criteria: -> { DeviceStat.all }, parent: "devices", split_label: "By page",
          search: [DEVICE_SEARCH]),
        "device-countries" => DailyReport::Breakdown.new(key: "device-countries", label: "Devices + countries", keys: %i[device country],
          headings: %w[Device Country], criteria: -> { CountryDeviceStat.all }, parent: "devices", split_label: "By country",
          search: [DEVICE_SEARCH, COUNTRY_SEARCH]),
        "device-technology" => DailyReport::Breakdown.new(key: "device-technology", label: "Devices + technology",
          keys: %i[device browser operating_system], headings: ["Device", "Browser", "Operating system"], criteria: -> { DeviceTechnologyStat.all },
          parent: "devices", split_label: "By browser and OS", search: [DEVICE_SEARCH, BROWSER_SEARCH]),
        "technology" => DailyReport::Breakdown.new(key: "technology", label: "Technology", keys: %i[browser operating_system],
          headings: ["Browser", "Operating system"], criteria: -> { TechnologyStat.all },
          search: [BROWSER_SEARCH]),
        "technology-pages" => DailyReport::Breakdown.new(key: "technology-pages", label: "Technology + pages", keys: %i[browser operating_system page_path],
          headings: ["Browser", "Operating system", "Page path"], criteria: -> { TechnologyStat.all }, parent: "technology", split_label: "By page",
          search: [BROWSER_SEARCH]),
        "technology-devices" => DailyReport::Breakdown.new(key: "technology-devices", label: "Technology + devices",
          keys: %i[browser operating_system device], headings: ["Browser", "Operating system", "Device"], criteria: -> { DeviceTechnologyStat.all },
          parent: "technology", split_label: "By device", search: [BROWSER_SEARCH, DEVICE_SEARCH]),
        "age" => DailyReport::Breakdown.new(key: "age", label: "Age", keys: [:age_bracket], headings: ["Age"],
          criteria: -> { AgeStat.all }, default_sort: {"age_bracket" => "asc"}, note: DEMOGRAPHICS_NOTE),
        "age-pages" => DailyReport::Breakdown.new(key: "age-pages", label: "Age + pages", keys: %i[age_bracket page_path],
          headings: ["Age", "Page path"], criteria: -> { AgeStat.all }, parent: "age", split_label: "By page", default_sort: {"age_bracket" => "asc"}, note: DEMOGRAPHICS_NOTE),
        "gender" => DailyReport::Breakdown.new(key: "gender", label: "Gender", keys: [:gender], headings: ["Gender"],
          criteria: -> { GenderStat.all }, note: DEMOGRAPHICS_NOTE),
        "gender-pages" => DailyReport::Breakdown.new(key: "gender-pages", label: "Gender + pages", keys: %i[gender page_path],
          headings: ["Gender", "Page path"], criteria: -> { GenderStat.all }, parent: "gender", split_label: "By page", note: DEMOGRAPHICS_NOTE),
        "languages" => DailyReport::Breakdown.new(key: "languages", label: "Languages", keys: [:language], headings: ["Language"],
          criteria: -> { LanguageStat.all },
          search: [LANGUAGE_SEARCH]),
        "language-pages" => DailyReport::Breakdown.new(key: "language-pages", label: "Languages + pages", keys: %i[language page_path],
          headings: ["Language", "Page path"], criteria: -> { LanguageStat.all }, parent: "languages", split_label: "By page",
          search: [LANGUAGE_SEARCH]),
        "screen-resolutions" => DailyReport::Breakdown.new(key: "screen-resolutions", label: "Screen resolution", keys: [:screen_resolution],
          headings: ["Screen resolution"], criteria: -> { ScreenResolutionStat.all },
          search: [RESOLUTION_SEARCH]),
        "screen-resolution-pages" => DailyReport::Breakdown.new(key: "screen-resolution-pages", label: "Screen resolution + pages", keys: %i[screen_resolution page_path],
          headings: ["Screen resolution", "Page path"], criteria: -> { ScreenResolutionStat.all }, parent: "screen-resolutions", split_label: "By page",
          search: [RESOLUTION_SEARCH]),
        # In time order rather than by views, so the busiest hours and days
        # read as a shape across the day and week.
        "time-of-day" => DailyReport::Breakdown.new(key: "time-of-day", label: "Time of day", keys: [:hour], headings: ["Hour"],
          criteria: -> { TimeOfDayStat.all }, default_sort: {"hour" => "asc"}),
        "time-of-day-pages" => DailyReport::Breakdown.new(key: "time-of-day-pages", label: "Time of day + pages", keys: %i[hour page_path],
          headings: ["Hour", "Page path"], criteria: -> { TimeOfDayStat.all }, parent: "time-of-day", split_label: "By page", default_sort: {"hour" => "asc"}),
        "day-of-week" => DailyReport::Breakdown.new(key: "day-of-week", label: "Day of week", keys: [:day_of_week], headings: ["Day"],
          criteria: -> { TimeOfDayStat.all }, default_sort: {"day_of_week" => "asc"}),
        # A weekday's own hours, since a Sunday morning and a Monday morning
        # draw different readers.
        "day-of-week-hours" => DailyReport::Breakdown.new(key: "day-of-week-hours", label: "Day of week + hours", keys: %i[day_of_week hour],
          headings: %w[Day Hour], criteria: -> { TimeOfDayStat.all }, parent: "day-of-week", split_label: "By hour",
          default_sort: {"day_of_week" => "asc", "hour" => "asc"}),
        "day-of-week-pages" => DailyReport::Breakdown.new(key: "day-of-week-pages", label: "Day of week + pages", keys: %i[day_of_week page_path],
          headings: ["Day", "Page path"], criteria: -> { TimeOfDayStat.all }, parent: "day-of-week", split_label: "By page", default_sort: {"day_of_week" => "asc"})
      }.freeze
      # The same traffic counts as Acquisition, so a country's figures read
      # against a source's.
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

      # Over every reader in the period, whichever breakdown is open, since
      # GA stores new and returning apart from these breakdowns.
      def load_page
        super
        @visitor_weeks = VisitorTypeStat.weekly_views(@period)
      end
    end
  end
end
