# encoding: UTF-8

class ApplicationController < ActionController::Base
  # The admin exposes shared blog data, so no page may be public by default.
  include Authentication
  include CsvExport

  allow_browser versions: :modern

  stale_when_importmap_changes

  private

  # Only plain strings, so a crafted param can't slip a query operator in.
  def selected_ids
    Array.wrap(params[:ids]).grep(String).compact_blank
  end
end
