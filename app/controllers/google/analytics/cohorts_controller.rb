# encoding: UTF-8

module Google
  module Analytics
    # Exists because new against returning readers can't say how long readers
    # keep coming back, or whether those won lately stay longer than before.
    class CohortsController < ApplicationController
      def show
        @result = CohortService.call
      end
    end
  end
end
