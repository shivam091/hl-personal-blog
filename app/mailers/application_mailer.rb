# encoding: UTF-8

# Actions deliver themselves, so every send is logged the same way.
class ApplicationMailer < ActionMailer::Base
  default from: -> { self.class.from_address }
  layout "mailer"
  helper_method :blog_name, :blog_url, :logo_url

  # As the blog's own header and footer show them, so mail reads as from the
  # same person as the blog's.
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

    def blog_name
      Mail::Address.new(from_address).display_name
    rescue Mail::Field::ParseError
      "Personal Blog"
    end

    def blog_url = Blog.url

    def logo_url = Blog.logo_url
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
    cc = " (cc: #{Array(message.cc).join(', ')})" if message.cc.present?
    Rails.logger.info "[#{trigger}] Delivered to #{Array(message.to).join(', ')}#{cc}"
    message
  rescue => e
    Rails.logger.error "[#{trigger}] Failed: #{e.message}"
    raise
  end
end
