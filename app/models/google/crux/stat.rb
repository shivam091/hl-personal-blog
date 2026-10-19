# encoding: UTF-8

module Google
  module Crux
    # Copied from the Chrome UX Report because its history API only reaches
    # back 40 weeks, too few to see whether a redesign made the blog faster
    # for real readers a year on.
    class Stat
      include Mongoid::Document
      include DailyStat

      METRICS = {
        "lcp" => "largest_contentful_paint",
        "inp" => "interaction_to_next_paint",
        "cls" => "cumulative_layout_shift",
        "fcp" => "first_contentful_paint",
        "ttfb" => "experimental_time_to_first_byte"
      }.freeze
      # Phones and desktops apart as well as together, since a slow phone
      # experience hides in the combined figure.
      FORM_FACTORS = {"ALL" => "All devices", "PHONE" => "Phones", "DESKTOP" => "Desktops"}.freeze
      THRESHOLDS = {
        "lcp" => [2500, 4000],
        "inp" => [200, 500],
        "cls" => [0.1, 0.25],
        "fcp" => [1800, 3000],
        "ttfb" => [800, 1800]
      }.freeze

      field :form_factor, type: String
      field :first_date, type: Date
      # 75th percentile because that is how Core Web Vitals are judged.
      field :p75, type: Hash, default: {}
      field :good, type: Hash, default: {}

      key_fields :form_factor

      index({date: 1, form_factor: 1}, {unique: true})

      validates :form_factor, inclusion: {in: FORM_FACTORS.keys}

      class << self
        def rating(metric, value)
          return if value.nil?

          good, poor = THRESHOLDS.fetch(metric)
          if value <= good then :good
          elsif value <= poor then :needs_improvement
          else :poor
          end
        end

        def to_csv(stats)
          CSV.generate do |csv|
            csv << [
              "Window from", "Window to", "Device",
              *METRICS.keys.flat_map { |metric| ["#{metric.upcase} p75", "#{metric.upcase} good share"] }
            ]
            stats.each do |stat|
              csv << [
                stat.first_date&.iso8601,
                stat.date.iso8601,
                stat.form_factor,
                *METRICS.keys.flat_map { |metric| [stat.p75[metric], stat.good[metric]&.round(4)] }
              ]
            end
          end
        end
      end
    end
  end
end
