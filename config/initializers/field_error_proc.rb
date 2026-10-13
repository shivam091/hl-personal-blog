# encoding: UTF-8

# Rails' default wrapper div breaks flex and grid layouts; messages belong
# next to the field they're about. A proc, so the class stays reloadable in
# development.
Rails.application.config.action_view.field_error_proc = proc do |html_tag, tag|
  InlineFieldErrors.call(html_tag, tag)
end
