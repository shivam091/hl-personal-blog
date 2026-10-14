# encoding: UTF-8

module PageStatsHelper
  # Busiest first so what matters is read first; ties fall back to the key
  # so the order doesn't shuffle between page loads.
  def ranked_counts(counts)
    counts.map { |key, count| [key, count.to_i] }.sort_by { |key, count| [-count, key.to_s] }
  end

  # The frontend keys days as strings; one it wrote oddly is shown as-is
  # rather than breaking the page.
  def day_label(day)
    tag.time(l(Date.iso8601(day.to_s)), datetime: day)
  rescue Date::Error
    day
  end

  def time_or_dash(time)
    time ? time_tag(time) : "—"
  end

  def page_view_stats(page_view)
    [
      [
        "Views",
        number_with_delimiter(page_view.visitor_count),
        "text-slate-900",
        "eye",
        "Every human view of this page, all time, a reader coming back counted each time. Bots are counted apart."],
      [
        "Unique visitors",
        number_with_delimiter(page_view.unique_visitor_count),
        "text-slate-900",
        "users",
        "Readers counted once a day by a keyed hash of their IP, all time: someone who came back on another day counts again, and readers sharing an IP count as one."
      ],
      [
        "Bot views",
        number_with_delimiter(page_view.bot_count),
        "text-slate-900",
        "activity",
        "Views from crawlers, told apart by their user agent and left out of every other figure."
      ],
      [
        "Countries",
        number_with_delimiter(page_view.countries.size),
        "text-slate-900",
        "globe",
        "Countries this page has had views from, all time."
      ]
    ]
  end

  # Times are set smaller to fit a tile, on the counts' line height so
  # they sit level with them.
  def page_like_stats(page_like)
    [
      [
        "Likes",
        number_with_delimiter(page_like.like_count),
        "text-slate-900",
        "heart",
        "Likes of this page, all time. Each IP address can like a page once."
      ],
      [
        "Countries",
        number_with_delimiter(page_like.countries.size),
        "text-slate-900",
        "globe",
        "Countries this page has been liked from. Likes from before they were dated have no country, so they aren't counted here."
      ],
      [
        "First liked",
        time_or_dash(page_like.created_at),
        "text-sm leading-7 text-slate-900",
        "clock",
        "When this page got its first like."
      ],
      [
        "Last liked",
        time_or_dash(page_like.updated_at),
        "text-sm leading-7 text-slate-900",
        "clock",
        "When this page got its latest like."
      ]
    ]
  end
end
