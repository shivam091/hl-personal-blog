# encoding: UTF-8

module IconHelper
  # One cached sprite so pages don't repeat SVG markup and icons stay
  # consistent. The stroke style is set here rather than in the sprite so
  # every symbol inherits it.
  #
  # Hidden from screen readers by default, since visible text usually names
  # the control; an icon standing alone needs a label or it has no name.
  def icon(name, size: 16, label: nil, **options)
    accessibility = label ? {role: "img", aria: {label: label}} : {aria: {hidden: true}}

    tag.svg(
      width: size,
      height: size,
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": 2,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      focusable: "false",
      class: ["shrink-0", options[:class]],
      **accessibility, **options) do
      safe_join([(tag.title(label) if label), tag.use(href: "#{asset_path("icons.svg")}##{name}")].compact)
    end
  end
end
