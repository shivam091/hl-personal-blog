# encoding: UTF-8

# Written by the blog as a reader leaves, just before their subscriber
# record is deleted, so who left, when and how outlasts the record.
class NewsletterUnsubscribe
  include Mongoid::Document
  include ReadOnly

  METHODS = {"link" => "Unsubscribe page", "one_click" => "One-click, from the mail app"}.freeze

  field :email, type: String
  field :country, type: String
  # camelCase because these are the frontend's own keys in the shared live database.
  field :subscribedAt, type: Time, as: :subscribed_at
  field :unsubscribedAt, type: Time, as: :unsubscribed_at
  field :source, type: String
  field :sourcePage, type: String, as: :source_page

  # Read from the raw document rather than declared as a field, since
  # Mongoid would define a reader named method over Object#method even
  # under an alias.
  def unsubscribe_method
    attributes["method"]
  end

  def method_label
    METHODS.fetch(unsubscribe_method.to_s) { unsubscribe_method.presence || "Unknown" }
  end

  # Nil when the subscriber record held no sign-up time to copy.
  def days_subscribed
    ((unsubscribed_at - subscribed_at) / 1.day).floor if subscribed_at && unsubscribed_at
  end
end
