# encoding: UTF-8

module NavigationHelper
  NavLink = Struct.new(:label, :full_label, :icon, :path, :current, keyword_init: true)
  NavMenu = Struct.new(:label, :icon, :links, keyword_init: true) do
    def current
      links.any?(&:current)
    end

    # A submenu's flyout needs a pointer to reach, so links listed together
    # can't rely on one.
    def flat_links
      links.flat_map do |link|
        next link unless link.is_a?(NavMenu)

        link.links.map { |sub| sub.dup.tap { |copy| copy.label = sub.full_label } }
      end
    end
  end

  class << self
    # So a submenu's link still names what it belongs to when it's listed
    # without its submenu.
    def sublabel(menu, item)
      item[:full_label] || "#{menu} #{item[:label].downcase_first}"
    end

    # So a page is named the same wherever its link appears without its
    # menus.
    def flat_entries(entries = Rails.application.config_for(:navigation).fetch(:links))
      entries.flat_map do |entry|
        next [entry] unless entry[:items]

        entry[:items].flat_map do |item|
          item[:items] ? item[:items].map { |sub| sub.merge(label: sublabel(item[:label], sub)) } : [item]
        end
      end
    end
  end

  def navigation
    navigation_entries.map { |entry| nav_entry(entry) }
  end

  # Read when rendering rather than at boot, so editing the file shows up
  # without restarting the server; the file is tiny, so this costs nothing.
  def navigation_entries
    Rails.application.config_for(:navigation).fetch(:links)
  end

  # Built from the same entries as the menus, so the two can't disagree.
  def nav_trail(entries)
    entry = entries.find(&:current)
    return [] unless entry
    return [[entry.label, entry.path]] unless entry.is_a?(NavMenu)

    link = entry.links.find(&:current)
    return [] unless link
    return [[entry.label, nil], [link.label, link.path]] unless link.is_a?(NavMenu)

    sub = link.links.find(&:current)
    sub ? [[entry.label, nil], [link.label, nil], [sub.label, sub.path]] : []
  end

  def add_breadcrumb(label, path = nil)
    page_breadcrumbs << [label, path]
  end

  def page_breadcrumbs
    @page_breadcrumbs ||= []
  end

  def current_nav_place(entries)
    trail = nav_trail(entries)
    [trail[0...-1].map(&:first), trail.last.first] if trail.any?
  end

  private

  def nav_entry(entry)
    return nav_link(entry) unless entry[:items]

    nav_menu(entry, entry[:items].map do |item|
      item[:items] ? submenu(item) : nav_link(item)
    end)
  end

  def submenu(entry)
    nav_menu(entry, entry[:items].map do |item|
      nav_link(item, full_label: NavigationHelper.sublabel(entry[:label], item))
    end)
  end

  def nav_menu(entry, links)
    NavMenu.new(label: entry[:label], icon: entry[:icon], links: links)
  end

  def nav_link(entry, full_label: entry[:label])
    path = public_send(:"#{entry[:route]}_path")

    # The root path is a prefix of everything, so it only matches exactly; others
    # match by whole segments, so /reports/content isn't current on /reports/content-decay.
    current = if path == root_path
      request.path == root_path
    else
      request.path == path || request.path.start_with?("#{path}/")
    end

    NavLink.new(
      label: entry[:label],
      full_label: full_label,
      icon: entry[:icon],
      path: path,
      current: current
    )
  end
end
