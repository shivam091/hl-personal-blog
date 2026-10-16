# encoding: UTF-8

# Analytics codes countries as ISO 3166-1 alpha-2 but Search Console as
# alpha-3 or by name, so everything is turned into alpha-2 to let the two
# sources be compared country by country.
class CountryCodes
  class << self
    # Upcased because Search Console's API sends codes in lowercase.
    def from_iso3(code)
      by_iso3[code.to_s.upcase]
    end

    # Search Console's exported reports give names rather than codes.
    def from_name(name)
      by_name[name.to_s.strip]
    end

    private

    # Read once per process; the file never changes while the app runs.
    def countries
      @countries ||= YAML.load_file(Rails.root.join("config/countries.yml")).freeze
    end

    def by_iso3
      @by_iso3 ||= countries.to_h { |code, country| [country.fetch("iso3"), code] }.freeze
    end

    def by_name
      @by_name ||= countries.flat_map { |code, country| country.fetch("names").map { |name| [name, code] } }.to_h.freeze
    end
  end
end
