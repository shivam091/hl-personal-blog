# encoding: UTF-8

module Google
  module Analytics
    # Exists because readers a day say how many came, not how many of the
    # month's readers keep coming back, which is what a regular readership is.
    class StickinessController < ApplicationController
      def show
        @period = Period.new(params)
        @result = StickinessService.call(@period)
      end
    end
  end
end
