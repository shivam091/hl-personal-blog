# encoding: UTF-8

# Exists so it's known whether entries grow the list and whether the mail
# announcing them gets through.
class NewsletterReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @newsletter = NewsletterStats.new(@period)
  end
end
