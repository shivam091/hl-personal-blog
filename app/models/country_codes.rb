# encoding: UTF-8

# Matches the ways Google codes or names a country back to the ISO 3166-1
# alpha-2 code every stat is stored by, from config/countries.yml.
class CountryCodes
  class << self
    # Search Console's API codes countries as alpha-3, in any case.
    def from_iso3(code)
      by_iso3[code.to_s.upcase]
    end

    # Search Console's exported reports name countries in English.
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
