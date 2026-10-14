# encoding: UTF-8

module FeedEntriesHelper
  FEED_ENTRY_CHIP_CLASS = "inline-flex rounded-full px-2 py-0.5 text-xs font-medium".freeze

  # Linked as the list's chips are, so a chip filters the same way wherever
  # it's clicked.
  def feed_entry_rows(entry)
    [
      ["Type", feed_entry_chip(entry.type.capitalize, {type: entry.type}, "bg-slate-900 text-white hover:bg-slate-700")],
      ["Categories", feed_entry_chips(entry.category_names, :category, "bg-indigo-50 text-indigo-700 hover:bg-indigo-100")],
      ["Tags", feed_entry_chips(entry.tag_names, :tag, "bg-slate-100 text-slate-700 hover:bg-slate-200")],
      ["Published", (time_tag(entry.published_at, l(entry.published_at)) if entry.published_at)],
      ["Updated", (time_tag(entry.last_modified_at, l(entry.last_modified_at)) if entry.last_modified_at)]
    ]
  end

  # Only http(s), since a javascript: address in the feed would run when the
  # link is clicked.
  def feed_entry_thumbnail_url(entry)
    entry.thumbnail_url if entry.thumbnail_url.to_s.match?(%r{\Ahttps?://}i)
  end

  private

  def feed_entry_chips(names, filter, colors)
    safe_join(names.map { |name| feed_entry_chip(name, {filter => name}, colors) }, " ").presence
  end

  def feed_entry_chip(text, filters, colors)
    link_to text, feed_entries_path(filters), class: "#{FEED_ENTRY_CHIP_CLASS} #{colors}"
  end
end
