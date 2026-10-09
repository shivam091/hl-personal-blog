# encoding: UTF-8

# Partial matches (passw catches password), so a sensitive value stays out
# of the logs whatever its param is called.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]
