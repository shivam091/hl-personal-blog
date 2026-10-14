# encoding: UTF-8

module NewsletterSubscribersHelper
  def newsletter_subscriber_rows(subscriber)
    [
      [NewsletterSubscriber.human_attribute_name(:email), subscriber.email],
      [NewsletterSubscriber.human_attribute_name(:country), subscriber.country],
      [NewsletterSubscriber.human_attribute_name(:subscribed_at), (time_tag(subscriber.subscribed_at) if subscriber.subscribed_at)]
    ]
  end
end
