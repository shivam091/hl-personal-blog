# encoding: UTF-8

module Google
  module Crux
    # Kept for longer than Google holds it, so whether the blog got faster or
    # slower for real readers can be seen across a year or more.
    class StatsController < ApplicationController
      def index
        @form_factor = params[:device].to_s.upcase.presence_in(Stat::FORM_FACTORS.keys) || Stat::FORM_FACTORS.keys.first
        @stats = Stat.where(form_factor: @form_factor).order(date: :asc).to_a

        respond_to do |format|
          format.html
          format.csv do
            send_csv Stat.to_csv(Stat.order(date: :asc, form_factor: :asc)),
                     filename: "web-vitals-history-#{Date.current.iso8601}.csv"
          end
        end
      end

      # Google returns every window it still holds on each call, so there's
      # no range to choose.
      def sync
        SyncRequest.enqueue("crux")
        redirect_to google_crux_stats_path,
                    notice: "Syncing the Chrome UX Report in the background. Refresh in a moment to see the latest windows."
      end
    end
  end
end
