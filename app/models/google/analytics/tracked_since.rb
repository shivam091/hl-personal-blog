# encoding: UTF-8

module Google
  module Analytics
    # The blog's tracking arrived feature by feature after it went live, and
    # GA neither backfills an event nor a custom dimension registered late,
    # so each date is the first day GA has the figure for. Without them a
    # period reaching back reads as readers who didn't do what they couldn't
    # yet be counted doing.
    module TrackedSince
      RELEASED = Date.new(2026, 6, 16)
      ANALYTICS = Date.new(2026, 6, 18)
      RESUME_DOWNLOADS = Date.new(2026, 9, 19)
      EVENT_LABELS = Date.new(2026, 10, 24)
      WEB_VITALS = Date.new(2026, 10, 30)
      CONTENT_GROUPS = Date.new(2026, 10, 30)
      CAMPAIGNS = Date.new(2026, 11, 1)
      EVENT_METHODS = Date.new(2026, 11, 16)

      ANALYTICS_NOTE = CountedSince.new(date: ANALYTICS, what: "Analytics figures",
        why: "two days after the blog went live on #{RELEASED.strftime("%-d %b, %Y")}")
    end
  end
end
