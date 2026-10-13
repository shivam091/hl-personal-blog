# encoding: UTF-8

module ApplicationHelper
  # Lets each list control change its own params without wiping out the
  # state the other controls put in the URL.
  def list_url(*states, **overrides)
    url_for(states.compact.map(&:query).reduce({}, :merge).merge(overrides).compact)
  end

  # URLs the frontend stores aren't validated here, and a javascript: one
  # would run in the admin's session when clicked.
  def http_url(url)
    uri = URI.parse(url.to_s)
    url if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # The button must come before every option, the blank one included, for
  # browsers that style the open list to show the choice through it; the
  # rest drop it and draw a plain select.
  def picker_select_tag(name, option_tags, include_blank: nil, **options)
    option_tags = options_for_select([[include_blank, ""]]) + option_tags if include_blank
    select_tag(name, tag.button(tag.selectedcontent) + option_tags, **options)
  end

  EXTERNAL_LINK_CLASS ="shrink-0 rounded text-slate-400 hover:text-slate-900"

  # The page readers see for a blog path or URL, on the same address as the
  # links in the blog's emails.
  def blog_live_url(path_or_url)
    value = path_or_url.to_s
    return http_url(value) if value.match?(%r{\Ahttps?://}i)

    origin = Blog.url
    "#{origin}#{value}" if origin.present? && value.start_with?("/")
  end

  # A blog page opens its page here, with the live page one click away in a
  # new tab, so what readers see can be checked from any list. With no page
  # here, the text is just text. Whole by default, so a table's column is as
  # wide as its data; cut off where a list's row has to keep its figures in
  # view.
  def blog_page_link(text, path, live: text, title: live, truncate: false)
    live_url = blog_live_url(live)
    text_class = "#{truncate ? "truncate" : "whitespace-nowrap"} font-medium text-slate-900 hover:underline"
    tag.span(class: ["flex items-center gap-1.5", truncate && "max-w-full min-w-0"]) do
      safe_join([
        path ? link_to(text, path, class: text_class, title: title) : tag.span(text, class: text_class.sub(" hover:underline", ""), title: title),
        (external_link(live_url, label: "Open #{text} on the blog") if live_url)
      ].compact)
    end
  end

  # A period's dates as time tags, read aloud as "from … to …". Compact
  # writes the year once when both ends share it, so a phone's period bar
  # fits the period and what it's compared with on one line.
  def period_dates(period, compact: false)
    label = lambda do |date, year: true|
      l(date, format: compact ? (year ? :compact : :day_month) : :default)
    end
    return time_tag(period.from, label.(period.from)) if period.from == period.to

    safe_join([
      time_tag(period.from, label.(period.from, year: period.from.year != period.to.year)),
      tag.span(" – ", aria: {hidden: "true"}),
      tag.span(" to ", class: "sr-only"),
      time_tag(period.to, label.(period.to))
    ])
  end

  # Icon-only, so it sits beside a link without competing with it.
  def external_link(url, label:)
    link_to(icon("external-link", size: 12), url, target: "_blank", rel: "noopener", title: "Open in a new tab",
      class: EXTERNAL_LINK_CLASS, aria: {label: label})
  end

  # Nested values stay readable instead of showing Ruby's inspect format.
  def log_value(value)
    case value
    when Hash, Array
      tag.pre(JSON.pretty_generate(value), class: "whitespace-pre-wrap break-all font-mono text-xs")
    when nil, ""
      tag.span("—", class: "text-slate-400")
    else
      value.to_s
    end
  end
end
