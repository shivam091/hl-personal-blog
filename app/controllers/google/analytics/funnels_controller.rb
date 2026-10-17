# encoding: UTF-8

module Google
  module Analytics
    # Exists so the step where readers drop out on the way to a conversion
    # is seen, not just how many made it.
    class FunnelsController < ApplicationController
      # Kept in the URL like the period, so changing either keeps the other.
      Choice = Struct.new(:breakdown, :next_action) do
        def query
          {breakdown: breakdown, next: next_action}.compact
        end
      end

      def show
        @period = Period.new(params)
        # Read once, so both periods ask GA the same funnels.
        definitions = FunnelDefinition.all_or_defaults
        @result = FunnelService.call(@period, breakdown: params[:breakdown], next_action: params[:next], definitions: definitions)
        @errors = @result.errors
        @choice = Choice.new(@result.breakdown, @result.next_action)
        # Only once a comparison is picked, as on every report, and without
        # next actions, which are only read for the period itself. A failed
        # earlier period only costs the comparison, so its errors are shown
        # beside the period's own rather than in their place.
        if @period.compare?
          previous = FunnelService.call(@period.previous, breakdown: @result.breakdown, definitions: definitions)
          @previous_funnels = previous.funnels.index_by(&:key)
          @errors = (@result.errors + previous.errors.map { |error| "#{@period.previous}: #{error}" }).uniq
        end

        respond_to do |format|
          format.html
          format.csv do
            breakdown = FunnelService::BREAKDOWNS.dig(@result.breakdown, :label)
            send_csv FunnelService.to_csv(@result.funnels, previous: @previous_funnels || {}),
              filename: "analytics-funnels#{"-by-#{@result.breakdown}" if breakdown}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
              detail: [@period.to_s, ("by #{breakdown.downcase}" if breakdown)].compact.join(", ")
          end
        end
      end
    end
  end
end
