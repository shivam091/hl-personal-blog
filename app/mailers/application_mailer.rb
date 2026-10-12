# encoding: UTF-8

# Actions deliver themselves, so every send is logged the same way. That's
# why a mailer is run with `.message`: `deliver_now` would send it again.
class ApplicationMailer < ActionMailer::Base
  default from: -> { self.class.from_address }
  layout "mailer"
  helper_method :blog_name, :blog_url, :logo_url

  # As the blog's own header and footer show them (siteConfig.author in the
  # frontend), so mail from here reads as from the same person as the blog's.
  ROLES = "Software engineer · Freelancer · Lifelong learner".freeze
  SOCIAL_LINKS = {
    "GitHub" => "https://github.com/shivam091",
    "LinkedIn" => "https://www.linkedin.com/in/shivam091",
    "Instagram" => "http://instagram.com/taurusian_soul"
  }.freeze

  class << self
    # From credentials, since Brevo only sends from an address verified there.
    def from_address
      Rails.application.credentials.dig(:mailer, :from)
    end

    # The sender's name, so the mail reads as from a person.
    def blog_name
      Mail::Address.new(from_address).display_name
    rescue Mail::Field::ParseError
      "Personal Blog"
    end

    # The sitemap's site, since the sitemap is the blog's own.
    def blog_url
      Rails.application.credentials.dig(:sitemap, :url).to_s[%r{\Ahttps?://[^/]+}]
    end

    # From the blog itself, which is always up, unlike this app on Render's
    # free plan, where a sleeping app would leave a broken image. A PNG, as
    # Gmail won't show SVG.
    def logo_url
      "#{blog_url}/assets/img/icons/favicon.png" if blog_url
    end
  end

  private

  def blog_name = self.class.blog_name

  def blog_url = self.class.blog_url

  def logo_url = self.class.logo_url

  # To the app's log rather than a file, since Render shows only what goes
  # to STDOUT and wipes its disk on every deploy.
  def deliver_with_logging(trigger)
    message = yield
    message.deliver!
    Rails.logger.info "[#{trigger}] Delivered to #{Array(message.to).join(', ')}" \
                            "#{" (cc: #{Array(message.cc).join(', ')})" if message.cc.present?}"
    message
  rescue => e
    Rails.logger.error "[#{trigger}] Failed: #{e.message}"
    raise
  end
end
