# encoding: UTF-8

module Google
  module Analytics
    class CohortsController < ApplicationController
      def show
        @result = CohortService.call(weeks: params[:weeks], country: params[:country], device: params[:device])
        @country = params[:country].to_s.upcase.presence
        @device = params[:device].presence_in(CohortService::DEVICES)
        # Only countries GA has sent readers from, so a pick can't come back empty for a typo.
        @countries = CountryStat.distinct(:country).reject { |code| code == SyncService::UNKNOWN_COUNTRY }.sort

        respond_to do |format|
          format.html
          format.csv do
            send_csv CohortService.to_csv(@result),
              filename: "analytics-cohorts-#{@result.weeks}-weeks-#{Date.current.iso8601}.csv",
              detail: ["#{@result.weeks} weeks", @country, @device].compact.join(", ")
          end
        end
      end
    end
  end
end
