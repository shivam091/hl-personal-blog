# encoding: UTF-8

module Google
  module Analytics
    # Exists so what readers search the blog for, and don't find, decides
    # what gets written next.
    class SiteSearchesController < ApplicationController
      def show
        @period = Period.new(params)
        @search = SiteSearch.new(@period)

        respond_to do |format|
          format.html
          format.csv do
            send_csv @search.to_csv,
                     filename: "site-search-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                     detail: "Site search terms, #{@period}"
          end
        end
      end
    end
  end
end
