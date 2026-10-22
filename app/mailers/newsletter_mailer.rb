# encoding: UTF-8

class NewsletterMailer < ApplicationMailer
  TYPE_LABELS = {"post" => "post", "tutorial" => "tutorial", "snippet" => "snippet", "series" => "series"}.freeze
  # Without these a mail client's click reaches GA with no referrer, and
  # reads as a direct visit. "email" is the medium GA files under its Email
  # channel.
  CAMPAIGN = {utm_source: "newsletter", utm_medium: "email", utm_campaign: "new_entry"}.freeze

  helper_method :campaign_url

  # One mail per subscriber rather than one to all, so no one sees the
  # others' addresses.
  def new_entry(entry, subscriber)
    deliver_with_logging(__method__) do
      @entry = entry
      @type = TYPE_LABELS.fetch(entry.type, "post")
      @home_url = campaign_url(blog_url, "header")
      to_emails = [subscriber.email]
      add_unsubscribe_links(subscriber)
      # Brevo hands the tag back on every event it posts for the mail, so
      # an open or click can be put down to the entry it announced.
      headers["X-Mailin-Tag"] = entry.url

      mail(to: to_emails, subject: "New #{@type}: #{entry.name}")
    end
  end

  private

  # utm_content names the link, so the title, the button and the footer
  # can be told apart in GA.
  def campaign_url(url, content)
    return url if url.blank?

    uri = URI.parse(url)
    uri.query = URI.encode_www_form(URI.decode_www_form(uri.query.to_s) + CAMPAIGN.merge(utm_content: content).to_a)
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  # On the blog rather than here, as the blog is always up, while this app
  # may be asleep when the link is clicked. Left out when the blog's address
  # isn't known, rather than linking somewhere that doesn't exist.
  def add_unsubscribe_links(subscriber)
    return unless blog_url

    token = subscriber.unsubscribe_token
    @unsubscribe_url = "#{blog_url}/unsubscribe/#{token}"
    # Gmail and Yahoo require one-click unsubscribe (RFC 8058) of bulk
    # senders, and post to this from their own unsubscribe button, which
    # can't show the confirm page.
    headers["List-Unsubscribe"] = "<#{blog_url}/api/unsubscribe/#{token}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
  end
end
