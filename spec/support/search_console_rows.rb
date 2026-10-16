# encoding: UTF-8

# The site's own query figures are its query × country rows added up, so a
# spec that sets a site-wide query's figures stores them as one country's:
# Search Console's unknown one, so no country a spec names is changed.
module SearchConsoleRows
  def search_console_row(model = Google::SearchConsole::Stat, **attributes)
    if model == Google::SearchConsole::Stat && attributes[:query] && attributes[:page].nil?
      model = Google::SearchConsole::QueryCountryStat
      attributes = {country: "ZZ"}.merge(attributes)
    end
    model.create!(**attributes)
  end
end

RSpec.configure { |config| config.include SearchConsoleRows }
