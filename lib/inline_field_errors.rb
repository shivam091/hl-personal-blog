# encoding: UTF-8

# Rails' default error markup wraps invalid fields in a div, which breaks
# flex and grid layouts and says nothing about what's wrong. A field's
# messages belong right below it, where the fix is made, and tied to it so
# screen readers announce them.
class InlineFieldErrors
  CONTROLS = %w[input select textarea].freeze

  class << self
    def call(html_tag, tag)
      new(html_tag, tag).to_html
    end
  end

  def initialize(html_tag, tag)
    @html_tag = html_tag
    @tag = tag
  end

  def to_html
    fragment = Nokogiri::HTML5::DocumentFragment.parse(@html_tag)
    control = fragment.element_children.first
    # Labels and a check box's hidden companion input pass through untouched,
    # so each message appears once, next to the visible control.
    return @html_tag unless control && CONTROLS.include?(control.name) && control["type"] != "hidden"

    error_id = "#{control["id"].presence || SecureRandom.hex(4)}_error"
    control["aria-invalid"] = "true"
    control["aria-describedby"] = [control["aria-describedby"], error_id].compact_blank.join(" ")

    # Every radio in a group would repeat the message; they're only marked.
    return control.to_html.html_safe if control["type"] == "radio"

    helpers.safe_join([
      control.to_html.html_safe,
      messages_html(error_id, check_box: control["type"] == "checkbox")
    ])
  end

  private

  def messages_html(error_id, check_box:)
    # Below the whole row, since a message between a check box and its label
    # would split them.
    helpers.tag.div(id: error_id, class: ["mt-1.5 space-y-1", ("order-last basis-full" if check_box)]) do
      helpers.safe_join(full_messages.map { |message| message_html(message) })
    end
  end

  def message_html(message)
    helpers.tag.p(class: "flex items-start gap-1.5 text-sm text-red-700") do
      helpers.safe_join([helpers.icon("alert-circle", size: 14, class: "mt-0.5"), helpers.tag.span(message)])
    end
  end

  # Full messages include the field's human name, so each one makes sense
  # read on its own, e.g. by a screen reader jumping to the field.
  def full_messages
    # The tag builder doesn't expose the attribute it was built for.
    @tag.object.errors.full_messages_for(@tag.instance_variable_get(:@method_name))
  end

  # The app's helpers, not just Rails', so the error icon comes from the
  # same sprite as every other icon.
  def helpers
    ApplicationController.helpers
  end
end
