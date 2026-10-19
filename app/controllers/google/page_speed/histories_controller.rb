# encoding: UTF-8

module Google
  module PageSpeed
    # So whether a page got slower after a change, and on which run, is seen
    # rather than guessed from its latest score alone.
    class HistoriesController < ApplicationController
      def show
        @url = params[:url].to_s
        @strategy = params[:device].to_s.presence_in(Result::STRATEGIES) || Result::STRATEGIES.first
        @runs = ResultHistory.runs(@url, @strategy).to_a
        raise ActionController::RoutingError, "No PageSpeed runs of #{@url}" if @runs.empty? && !Result.where(url: @url).exists?

        respond_to do |format|
          format.html
          format.csv do
            send_csv Result.to_csv(@runs.reverse), filename: "pagespeed-history-#{@strategy}-#{Date.current.iso8601}.csv",
              detail: "#{@url}, #{@strategy}"
          end
        end
      end
    end
  end
end
