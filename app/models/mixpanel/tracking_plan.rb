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
    METHOD = {"method" => Property.new("string", "How it was triggered: button, shortcut, palette, floating or inline.")}.freeze
    VITAL = {
      "value" => Property.new("integer", "The change since the last report (CLS × 1000), so a sum gives the final value."),
      "metric_value" => Property.new("number", "The metric's value at this report."),
      "metric_rating" => Property.new("string", "Google's band: good, needs-improvement or poor."),
      "metric_id" => Property.new("string", "Identifies one page load's metric, across its reports.")
    }.freeze

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
      "scroll_depth" => ["A reader got 25, 50, 75 or 100% down a post, tutorial, snippet or series.", {
        **LABEL, "percent" => Property.new("integer", "The milestone reached.")
      }],
      "article_read" => ["A reader reached the end of an article after at least 10 visible seconds.", {
        **LABEL, "read_seconds" => Property.new("integer", "Visible seconds before reaching the end.")
      }],
      "outbound_click" => ["A click on a link to another site.", {
        "link_url" => Property.new("string", "Where the link goes."),
        "link_domain" => Property.new("string", "The link's host."),
        "link_text" => Property.new("string", "The link's text, cut at 100 characters.")
      }],
      "text_copy" => ["A reader copied 20 or more characters of the page by selecting them.", {
        **LABEL, "copied_length" => Property.new("integer", "Characters copied.")
      }],
      "print" => ["A reader printed the page.", LABEL],
      "js_error" => ["An uncaught script error in the reader's browser, at most five per page load.", {
        "error_kind" => Property.new("string", "error or unhandled_rejection."),
        "error_message" => Property.new("string", "The error's message."),
        "error_source" => Property.new("string", "The script it came from."),
        "error_line" => Property.new("integer", "The line in that script."),
        "path" => Property.new("string", "The page's path.")
      }],
      "theme_change" => ["A reader switched colour theme.", {
        "theme" => Property.new("string", "The theme picked."), "previous_theme" => Property.new("string", "The theme before.")
      }],
      "sound_toggle" => ["A reader switched interface sounds on or off.", {**LABEL, "event_category" => Property.new("string", "preference")}],
      "consent_choice" => ["A reader answered the cookie banner.", {
        "choice" => Property.new("string", "granted or denied."), "previous_choice" => Property.new("string", "Their answer before, or pending.")
      }],
      "copy_code" => ["A code block copied with its copy button.", {**LABEL, "event_category" => Property.new("string", "engagement")}],
      "cover_image_open" => ["A reader opened an entry's cover image full size.", LABEL],
      "like" => ["A reader liked the page.", {**LABEL, **METHOD}],
      "page_not_found" => ["A reader landed on a missing page.", LABEL],
      "sandbox_run" => ["A code sandbox was run.", {**LABEL, **METHOD}],
      "sandbox_reset" => ["A code sandbox was reset.", {**LABEL, **METHOD}],
      "sandbox_download" => ["A code sandbox was downloaded as a zip.", {**LABEL, **METHOD}],
      "sandbox_open_external" => ["A code sandbox was opened in CodeSandbox.", LABEL],
      "view_search_results" => ["A site search that found something.", {
        "search_term" => Property.new("string", "What was searched for, lowercased."),
        "results_count" => Property.new("integer", "How many results it found.")
      }],
      "search_no_results" => ["A site search that found nothing.", {"search_term" => Property.new("string", "What was searched for, lowercased.")}],
      "search_result_click" => ["A click on a site search result.", LABEL],
      "toc_click" => ["A click in an entry's table of contents.", LABEL],
      "related_click" => ["A click on a related entry.", LABEL],
      "prev_next_click" => ["A click on the previous or next entry.", LABEL],
      "core_stack_click" => ["A click on an item in the core stack.", LABEL],
      "share" => ["A reader shared the page.", LABEL],
      "show_more" => ["A reader expanded a list.", LABEL],
      "newsletter_form_seen" => ["A newsletter form came into view, once per page.", {
        **LABEL, "form_source" => Property.new("string", "Which form: footer, article_end or article_inline.")
      }],
      "newsletter_form_started" => ["A reader began typing into a newsletter form, once per page.", {
        **LABEL, "form_source" => Property.new("string", "Which form: footer, article_end or article_inline.")
      }],
      "newsletter_subscribe" => ["A newsletter subscription, sent by the server once it's stored.", {
        "source" => Property.new("string", "server")
      }],
      "newsletter_unsubscribe" => ["A newsletter unsubscription, sent by the server.", {"source" => Property.new("string", "server")}],
      "contact_submit" => ["A contact-form message, sent by the server once it's stored.", {"source" => Property.new("string", "server")}],
      **%w[LCP INP CLS FCP TTFB].to_h { |metric| [metric, ["A Web Vitals report for #{metric}.", VITAL]] }
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
