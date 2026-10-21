# encoding: UTF-8

class ContentDecayReportsController < ApplicationController
  FILTER_FIELDS = [
    Filtering::Select.new(:type, field: :type, label: "Type", blank_label: "Every type", choices: FeedEntry::TYPES.index_with(&:capitalize)),
    Filtering::Select.new(:min_age, field: :min_age, label: "Not updated for", blank_label: "Any time", choices: ContentDecay::MIN_AGES)
  ].freeze

  def show
    @period = Period.new(params)
    @filtering = Filtering.new(params, fields: FILTER_FIELDS)
    search = Google::SearchConsole::Summary.new(@period)
    @decay = ContentDecay.new(ContentStats.new(BlogStats.new(@period), search: search),
      Google::SearchConsole::Opportunities.new(@period, summary: search),
      type: @filtering.values[:type], min_age_months: @filtering.values[:min_age])

    respond_to do |format|
      format.html
      format.csv do
        send_csv @decay.to_csv, filename: "content-decay-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
          detail: ["Content decay", @period, *@filtering.chips.map(&:first)].join(", ")
      end
    end
  end
end
