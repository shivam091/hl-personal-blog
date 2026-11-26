# encoding: UTF-8

module Mixpanel
  # What the blog sends, written down once, so Mixpanel's Lexicon can say
  # what each event and property means to anyone reading a report there.
  # Kept with the code that reads the events, since a change to either
  # should change both.
  module TrackingPlan
    Property = Struct.new(:type, :description)

    # On every event the browser sends, registered once per visit or page.
    COMMON = {
      "consent_status" => Property.new("string", "The reader's cookie answer: granted, or default where no banner is needed."),
      "content_group" => Property.new("string", "What the page is: post, tutorial, snippet, series, listing or page."),
      "content_category" => Property.new("string", "A post's category slug, or (none)."),
      "content_tags" => Property.new("string", "The entry's tags, comma-separated, or (none)."),
      "ga_status" => Property.new("string", "Whether gtag loaded for this reader (loaded), was blocked (blocked) or never started (off)."),
      "ga_client_id" => Property.new("string", "GA's client ID from the _ga cookie, to match a reader across GA and Mixpanel."),
      "theme" => Property.new("string", "The colour theme picked: light, dark, soft-dark or system."),
      "prefers_reduced_motion" => Property.new("boolean", "Whether the reader's system asks for reduced motion."),
      "prefers_dark" => Property.new("boolean", "Whether the reader's system prefers a dark colour scheme.")
    }.freeze

    LABEL = {"event_label" => Property.new("string", "The page path or item the event concerns.")}.freeze
    FORM_SOURCE = {"form_source" => Property.new("string", "Which form: footer, article_end or article_inline.")}.freeze

    # Only what Mixpanel's own reports are built on; every other event goes
    # to GA alone, so the two don't hold the same counts twice.
    EVENTS = {
      "$mp_web_page_view" => ["A page opened, sent once its title is in.", {
        "page_title" => Property.new("string", "The page's title."),
        "page_location" => Property.new("string", "The page's URL without its fragment.")
      }],
      "page_leave" => ["The end of a page view (or its tab being hidden), with how it was read. Resent with growing totals; count the last per view_id.", {
        "view_id" => Property.new("string", "One page view, across its page_leave events."),
        "path" => Property.new("string", "The page's path."),
        "engaged_seconds" => Property.new("integer", "Seconds the tab was visible and the reader active within the last 30 seconds."),
        "max_scroll_percent" => Property.new("integer", "How far down the page the reader got, 0 to 100.")
      }],
      "article_read" => ["A reader reached the end of an article after at least 10 visible seconds.", {
        **LABEL, "read_seconds" => Property.new("integer", "Visible seconds before reaching the end.")
      }],
      "js_error" => ["An uncaught script error in the reader's browser, at most five per page load.", {
        "error_kind" => Property.new("string", "error or unhandled_rejection."),
        "error_message" => Property.new("string", "The error's message."),
        "error_source" => Property.new("string", "The script it came from."),
        "error_line" => Property.new("integer", "The line in that script."),
        "path" => Property.new("string", "The page's path.")
      }],
      "newsletter_form_seen" => ["A newsletter form came into view, once per page.", {**LABEL, **FORM_SOURCE}],
      "newsletter_form_started" => ["A reader began typing into a newsletter form, once per page.", {**LABEL, **FORM_SOURCE}],
      "newsletter_form_focused" => ["A reader focused a newsletter form's email field, once per page.", {**LABEL, **FORM_SOURCE}],
      "newsletter_form_submitted" => ["A reader submitted a newsletter form, each attempt.", {**LABEL, **FORM_SOURCE}],
      "newsletter_form_error" => ["A newsletter form submit that failed, with the message shown.", {
        **LABEL, **FORM_SOURCE, "error_message" => Property.new("string", "The message the reader saw, cut at 100 characters.")
      }],
      "newsletter_subscribe" => ["A newsletter subscription, sent by the server once it's stored.", {
        "source" => Property.new("string", "server")
      }],
      "newsletter_unsubscribe" => ["A newsletter unsubscription, sent by the server.", {"source" => Property.new("string", "server")}],
      "contact_submit" => ["A contact-form message, sent by the server once it's stored.", {"source" => Property.new("string", "server")}]
    }.freeze

    SUBSCRIBER_PROFILE = {
      "subscribed" => Property.new("boolean", "Whether the reader is subscribed to the newsletter now."),
      "subscribed_at" => Property.new("string", "When they subscribed."),
      "unsubscribed_at" => Property.new("string", "When they unsubscribed, if they have."),
      "newsletter_source" => Property.new("string", "Which form they subscribed through."),
      "source_page" => Property.new("string", "The page they subscribed on.")
    }.freeze

    def self.entries
      events = EVENTS.map do |name, (description, properties)|
        server = description.include?("sent by the server")
        {entityType: "event", name: name, schemaJson: schema(description, server ? properties : COMMON.merge(properties))}
      end
      events << {entityType: "profile", name: "$user", schemaJson: schema("A newsletter subscriber, named by a keyed hash of their email.", SUBSCRIBER_PROFILE)}
    end

    def self.schema(description, properties)
      {description: description, properties: properties.transform_values { |property| {type: property.type, description: property.description} }}
    end
  end
end
