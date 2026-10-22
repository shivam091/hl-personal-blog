# encoding: UTF-8

module NewsletterSubscribersHelper
  def newsletter_subscriber_rows(subscriber)
    [
      [NewsletterSubscriber.human_attribute_name(:email), subscriber.email],
      [NewsletterSubscriber.human_attribute_name(:country), subscriber.country],
      [NewsletterSubscriber.human_attribute_name(:subscribed_at), (time_tag(subscriber.subscribed_at) if subscriber.subscribed_at)],
      ["Signed up through", subscriber.source_label],
      ["Signed up on", (blog_page_link(subscriber.source_page, page_view_path(subscriber.source_page), live: subscriber.source_page) if subscriber.source_page.present?)]
    ]
  end
end
