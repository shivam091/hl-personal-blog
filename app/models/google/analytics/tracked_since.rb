# encoding: UTF-8

module Google
  module Analytics
    # GA has no data for the days before the property was set up, so a
    # baseline built from earlier weeks has nothing to count there.
    module TrackedSince
      ANALYTICS = Date.new(2026, 6, 18)
    end
  end
end
