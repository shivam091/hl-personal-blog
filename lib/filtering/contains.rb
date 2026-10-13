# encoding: UTF-8

class Filtering
  # The text is escaped so typed punctuation can't act as a regex.
  class Contains
    attr_reader :name, :field, :label, :placeholder

    def initialize(name, field:, label:, placeholder: nil)
      @name, @field, @label, @placeholder = name, field, label, placeholder
    end

    def read(params)
      {name => params[name].to_s.strip.presence}
    end

    def apply(scope, values)
      values[name] ? scope.where(field => /#{Regexp.escape(values[name])}/i) : scope
    end

    def chips(values)
      values[name] ? [["#{label} “#{values[name]}”", name]] : []
    end

    def to_partial_path
      "shared/filtering/fields/contains"
    end
  end
end
