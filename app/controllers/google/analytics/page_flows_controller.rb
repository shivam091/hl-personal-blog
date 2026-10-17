# encoding: UTF-8

module Google
  module Analytics
    class PageFlowsController < ApplicationController
      # Kept in the URL like the period, so changing either keeps the other.
      Choice = Struct.new(:path) do
        def query
          {path: path}.compact
        end
      end
      PAGES_OFFERED = 50

      def show
        @period = Period.new(params)
        @pages = Stat.grouped(@period.apply(Stat.all), by: [:page_path]).map { |row| [row[:page_path], row.views] }
          .reject { |path, _| path.blank? }.sort_by { |path, views| [-views, path] }.first(PAGES_OFFERED).map(&:first)
        @path = PageFlowService.path(params[:path]) || @pages.first || "/"
        @choice = Choice.new(@path)
        @result = PageFlowService.call(@period, path: @path)
        # Left out when GA can't give it, since the period itself still reads.
        previous = PageFlowService.call(@period.previous, path: @path) if @period.compare? && @result.errors.empty?
        @previous_flow = previous.flow if previous&.errors&.empty?
      end
    end
  end
end
