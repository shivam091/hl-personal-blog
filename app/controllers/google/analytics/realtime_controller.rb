# encoding: UTF-8

module Google
  module Analytics
    class RealtimeController < ApplicationController
      def show
        @snapshot = RealtimeService.call
      end
    end
  end
end
