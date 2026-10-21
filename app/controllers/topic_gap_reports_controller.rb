# encoding: UTF-8

class TopicGapReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @filtering = Filtering.new(params, fields: [country_field, impressions_field])
    @gaps = TopicGaps.new(@period, country: @filtering.values[:country],
      min_impressions: (@filtering.values[:min_impressions] || TopicGaps::DEFAULT_MIN_IMPRESSIONS).to_i)

    respond_to do |format|
      format.html
      format.csv do
        export = params[:export].presence_in(TopicGaps::EXPORTS.keys) || TopicGaps::EXPORTS.keys.first
        send_csv @gaps.to_csv(export), filename: "topic-gaps-#{export}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
          detail: [TopicGaps::EXPORTS[export], @period, *@filtering.chips.map(&:first)].join(", ")
      end
    end
  end

  private

  # Only countries Search Console has queries from in the period, so none
  # offered reads as empty.
  def country_field
    codes = Google::SearchConsole::QueryCountryStat.where(date: @period.from..@period.to).distinct(:country).compact.sort
    Filtering::Select.new(:country, field: :country, label: "Country", blank_label: "All countries",
      choices: codes.index_with { |code| helpers.country_label(code) })
  end

  def impressions_field
    Filtering::Select.new(:min_impressions, field: :min_impressions, label: "Impressions",
      blank_label: "#{TopicGaps::DEFAULT_MIN_IMPRESSIONS}+", choices: TopicGaps::MIN_IMPRESSIONS.except(TopicGaps::DEFAULT_MIN_IMPRESSIONS.to_s))
  end
end
