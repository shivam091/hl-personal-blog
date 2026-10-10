# encoding: UTF-8

class ApplicationController < ActionController::Base
  # The admin exposes shared blog data, so no page may be public by default.
  include Authentication

  allow_browser versions: :modern

  stale_when_importmap_changes
end
