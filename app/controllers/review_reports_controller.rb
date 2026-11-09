# encoding: UTF-8

# Exists so a month or a year can be looked back on in one place, rather
# than pieced together from every report.
class ReviewReportsController < ApplicationController
  def show
    @spans = Review.spans
    @span = Review.span(params[:span])
    @period = @span.period
    stats = BlogStats.new(@period)
    @review = Review.new(stats, search: Google::SearchConsole::Summary.new(@period), analytics: Google::Analytics::Summary.new(@period),
      ai: Google::SearchConsole::GenerativeAiSummary.new(@period))

    respond_to do |format|
      format.html
      format.csv do
        send_csv @review.to_csv, filename: "review-#{@span.key}.csv", detail: "Review of #{@span.label}"
      end
    end
  end
end
