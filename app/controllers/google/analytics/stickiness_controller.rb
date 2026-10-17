# encoding: UTF-8

module Google
  module Analytics
    class StickinessController < ApplicationController
      def show
        @period = Period.new(params)
        @result = StickinessService.call(@period)
        # Left out when GA can't give it, since the period itself still reads.
        previous = StickinessService.call(@period.previous) if @period.compare? && @result.errors.empty?
        @previous = previous if previous&.errors&.empty? && previous.any?
      end
    end
  end
end
