# encoding: UTF-8

class Filtering
  # Lets the reader narrow a time field to whole days, so picking a single
  # day includes everything on it; bad dates are ignored rather than
  # breaking the list.
  class DateRange
    attr_reader :name, :field, :label

    def initialize(name, field:, label:)
      @name, @field, @label = name, field, label
    end

    def from_param
      :"#{name}_from"
    end

    def to_param
      :"#{name}_to"
    end

    def read(params)
      {from_param => parse(params[from_param]), to_param => parse(params[to_param])}
    end

    def apply(scope, values)
      bounds = {}
      bounds["$gte"] = values[from_param].beginning_of_day if values[from_param]
      bounds["$lte"] = values[to_param].end_of_day if values[to_param]
      bounds.empty? ? scope : scope.where(field => bounds)
    end

    def chips(values)
      [
        (["#{label} from #{I18n.l(values[from_param])}", from_param] if values[from_param]),
        (["#{label} to #{I18n.l(values[to_param])}", to_param] if values[to_param])
      ].compact
    end

    def to_partial_path
      "shared/filtering/fields/date_range"
    end

    private

    def parse(value)
      Date.iso8601(value) if value.present?
    rescue Date::Error
      nil
    end
  end
end
