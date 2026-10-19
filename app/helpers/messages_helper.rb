# encoding: UTF-8

module MessagesHelper
  # So borderline messages stand out while scanning; 0.7 matches the score
  # tabs so a badge never disagrees with the tab it's listed under.
  def recaptcha_score_badge(score)
    return "—" unless score

    tag.span(number_with_precision(score, precision: 1), class: ["rounded-full px-2 py-0.5 text-xs font-medium tabular-nums",
      score >= 0.7 ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-800"])
  end

  def message_verdict_badge(review)
    return unless review

    tag.span(review.label, class: ["rounded-full px-2 py-0.5 text-xs font-medium", review.spam? ? "bg-red-100 text-red-800" : "bg-emerald-100 text-emerald-800"])
  end

  # Both always offered, so a mis-click is undone with the other.
  def message_verdict_buttons(message, review, icon_only: false)
    safe_join(MessageReview::VERDICTS.map do |verdict, details|
      current = review&.verdict == verdict
      spam = verdict == "spam"
      title = current ? "Marked as #{details[:label].downcase}" : "Mark as #{details[:label].downcase}"
      classes =
        if icon_only
          [
            "inline-flex rounded-md p-1.5",
            if current then spam ? "text-red-600" : "text-emerald-600"
            else "text-slate-500 hover:bg-slate-100 hover:text-slate-900"
            end
          ]
        else
          [
            "inline-flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium shadow-sm",
            if current then spam ? "border-red-200 bg-red-50 text-red-800" : "border-emerald-200 bg-emerald-50 text-emerald-800"
            else "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
            end
          ]
        end

      button_to review_message_path(message, verdict: verdict), method: :patch, form_class: "inline-flex",
        disabled: current, title: title, class: classes,
        aria: {pressed: current, label: (icon_only ? "#{title}: message from #{message.name}" : nil)} do
        verdict_icon = icon(spam ? "alert-triangle" : "check-circle", size: icon_only ? 16 : 14)
        icon_only ? verdict_icon : safe_join([verdict_icon, details[:label]])
      end
    end)
  end

  # Whether Google heard, since a verdict only teaches it once sent.
  def message_feedback_status(message, review)
    if review.nil?
      "Not marked yet"
    elsif review.annotated_at
      safe_join(["Sent to reCAPTCHA ", time_tag(review.annotated_at)])
    elsif review.annotation_error
      tag.span("Not sent: #{review.annotation_error}", class: "text-amber-700")
    elsif message.recaptcha_assessment.blank?
      tag.span("Not sent: no reCAPTCHA assessment was kept with this message", class: "text-slate-500")
    else
      "Sending to reCAPTCHA…"
    end
  end

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
