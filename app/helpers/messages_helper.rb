# encoding: UTF-8

module MessagesHelper
  # So borderline messages stand out while scanning; 0.7 matches the score
  # tabs so a badge never disagrees with the tab it's listed under.
  def recaptcha_score_badge(score)
    return "—" unless score

    tag.span(number_with_precision(score, precision: 1), class: ["rounded-full px-2 py-0.5 text-xs font-medium tabular-nums",
      score >= 0.7 ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-800"])
  end

  # Newsletter status matters because a subscriber's message is worth
  # answering differently.
  def message_rows(message)
    subscriber = message.subscriber
    [
      [Message.human_attribute_name(:email), message.email],
      [Message.human_attribute_name(:country), message.country],
      [Message.human_attribute_name(:recaptcha_score), recaptcha_score_badge(message.recaptcha_score)],
      ["reCAPTCHA assessment", message.recaptcha_assessment.presence || "—"],
      [Message.human_attribute_name(:created_at), (time_tag(message.created_at) if message.created_at)],
      ["Newsletter", subscriber ? link_to("Subscribed", newsletter_subscriber_path(subscriber), class: "underline hover:text-slate-600") : "Not subscribed"]
    ]
  end
end
