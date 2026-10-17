# encoding: UTF-8

module Google
  module Analytics
    # Exists because a page's views say how many came, not where from or
    # where they went next, which is what decides the links an entry needs.
    class PageFlowsController < ApplicationController
      # Kept in the URL like the period, so changing either keeps the other.
      Choice = Struct.new(:path) do
        def query
          {path: path}.compact
        end
      end
      # Offered to pick from; any other path can still be typed.
      PAGES_OFFERED = 50

      def show
        @period = Period.new(params)
        @pages = Stat.grouped(@period.apply(Stat.all), by: [:page_path]).map { |row| [row[:page_path], row.views] }
          .reject { |path, _| path.blank? }.sort_by { |path, views| [-views, path] }.first(PAGES_OFFERED).map(&:first)
        # The most read page until one is picked, so the page opens on a flow.
        @path = PageFlowService.path(params[:path]) || @pages.first || "/"
        @choice = Choice.new(@path)
        @result = PageFlowService.call(@period, path: @path)
      end
    end
  end
end
