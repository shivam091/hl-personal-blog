# encoding: UTF-8

# Mailer actions deliver themselves, and development sends through the live relay when its credentials are
# present, so a preview renders with the test delivery swapped in rather than mailing anyone.
module UndeliveredPreview
  private

  def undelivered
    previous = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    yield.message
  ensure
    ActionMailer::Base.delivery_method = previous
  end
end
