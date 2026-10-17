# encoding: UTF-8

module Google
  module Analytics
    # Exists so the step where readers drop out on the way to a conversion
    # is seen, not just how many made it.
    class FunnelsController < ApplicationController
      def show
        @period = Period.new(params)
        @result = FunnelService.call(@period)
        @errors = @result.errors
        # Only once a comparison is picked, as on every report. A failed
        # earlier period only costs the comparison, so its errors are shown
        # beside the period's own rather than in their place.
        return unless @period.compare?

        previous = FunnelService.call(@period.previous)
        @previous_funnels = previous.funnels.index_by(&:key)
        @errors = (@result.errors + previous.errors.map { |error| "#{@period.previous}: #{error}" }).uniq
      end
    end
  end
end
