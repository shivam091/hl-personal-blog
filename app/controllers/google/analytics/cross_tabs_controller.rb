# encoding: UTF-8

module Google
  module Analytics
    # Exists because each report splits readers one way at a time, so how
    # two splits meet, like which channels bring mobile readers, can't be read.
    class CrossTabsController < ApplicationController
      # Kept in the URL like the period, so changing either keeps the other.
      Choice = Struct.new(:rows, :columns, :metric) do
        def query
          {rows: rows, columns: columns, metric: metric}.compact
        end
      end

      def show
        @period = Period.new(params)
        @result = PivotService.call(@period, rows: params[:rows], columns: params[:columns], metric: params[:metric])
        @choice = Choice.new(@result.rows, @result.columns, @result.metric)
        # The same split and count, so each cell has one to be judged against;
        # left out when GA can't give it, as the period itself still reads.
        if @period.compare? && @result.errors.empty?
          previous = PivotService.call(@period.previous, rows: @result.rows, columns: @result.columns, metric: @result.metric)
          @previous = previous if previous.errors.empty?
        end

        respond_to do |format|
          format.html
          format.csv do
            labels = [@result.rows, @result.columns].map { |key| PivotService::DIMENSIONS.dig(key, :label).downcase }
            send_csv PivotService.to_csv(@result, @previous),
              filename: "analytics-cross-tab-#{@result.metric}-by-#{@result.rows}-and-#{@result.columns}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
              detail: [@period.to_s, PivotService::METRICS.dig(@result.metric, :label), "by #{labels.join(" and ")}"].join(", ")
          end
        end
      end
    end
  end
end
