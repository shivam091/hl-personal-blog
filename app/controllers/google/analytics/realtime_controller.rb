# encoding: UTF-8

module Google
  module Analytics
    # Exists because the daily reports only show a spike, such as just after
    # a post is shared, days later.
    class RealtimeController < ApplicationController
      def show
        @snapshot = RealtimeService.call
      end
    end
  end
end
