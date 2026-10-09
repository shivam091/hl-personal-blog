# Expiring, so closing the browser or installed app can't sign the admin out
# before Authentication::SESSION_TTL does. Matched to it by hand, as that
# constant can't be autoloaded this early in boot.
#
# Key kept from before, so sessions already signed in survive.
Rails.application.config.session_store :cookie_store, key: "_hl_personal_blog_session", expire_after: 12.hours
