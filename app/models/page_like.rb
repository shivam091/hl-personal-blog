# encoding: UTF-8

require "csv"

class PageLike
  include Mongoid::Document
  include ReadOnly
  include DatedByDay

  CSV_HEADERS = ["URL", "Likes", "Countries", "First liked", "Last liked"].freeze

  field :slug, type: String
  field :url, type: String
  # camelCase because these are the frontend's own keys in the shared live database.
  field :likeCount, type: Integer, default: 0, as: :like_count
  field :countriesByDay, type: Hash, default: {}, as: :countries_by_day
  field :createdAt, type: Time, as: :created_at
  field :updatedAt, type: Time, as: :updated_at

  # Summed from the dated breakdown so the frontend only stores each like once.
  def likes_by_day
    countries_by_day.transform_values { |counts| counts.sum { |_, count| count.to_i } }
  end

  # Summed across days for the same reason as likes_by_day.
  def countries
    countries_by_day.each_value.with_object({}) do |day, totals|
      day.each { |code, count| totals[code] = totals.fetch(code, 0) + count.to_i }
    end
  end

  def likes_within(period)
    countries_within(period).values.sum
  end

  # ISO days sort as dates, so the period is compared as strings.
  def countries_within(period)
    from, to = period.from.iso8601, period.to.iso8601
    countries_by_day.each_with_object(Hash.new(0)) do |(day, counts), totals|
      counts.each { |code, count| totals[code] += count.to_i } if day.between?(from, to)
    end
  end

  class << self
    # Likes were only dated from some day, so a period reaching back before
    # it shows none rather than few.
    def first_day
      first_day_in(%w[countriesByDay])
    end

    def to_csv(page_likes = order(like_count: :desc), period: nil)
      CSV.generate do |csv|
        csv << CSV_HEADERS
        page_likes.each do |page_like|
          countries = period ? page_like.countries_within(period) : page_like.countries
          csv << [
            page_like.url,
            period ? page_like.likes_within(period) : page_like.like_count,
            countries.sort_by { |_, count| -count }.map { |code, count| "#{code}: #{count}" }.join("; ").presence,
            page_like.created_at&.utc&.iso8601(3),
            page_like.updated_at&.utc&.iso8601(3)
          ]
        end
      end
    end
  end
end
