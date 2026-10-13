# encoding: UTF-8

class Filtering
  # A fragment finds every value like it, but a value picked from a list
  # must match only itself, or "css" would bring "css grid" along. Exact is
  # its own param, so a link can ask for it and a typed search needn't.
  class Match
    attr_reader :name, :field, :label, :placeholder

    def initialize(name, field:, label:, placeholder: nil)
      @name, @field, @label, @placeholder = name, field, label, placeholder
    end

    def match_param
      :"#{name}_match"
    end

    def read(params)
      value = params[name].to_s.strip.presence
      {name => value, match_param => ("exact" if value && params[match_param] == "exact")}
    end

    def apply(scope, values)
      return scope unless values[name]

      scope.where(field => values[match_param] ? values[name] : /#{Regexp.escape(values[name])}/i)
    end

    def chips(values)
      return [] unless values[name]

      [["#{label} #{values[match_param] ? "is" : "contains"} “#{values[name]}”", name]]
    end

    def exact_query(value)
      {name => value, match_param => "exact"}
    end

    def to_partial_path
      "shared/filtering/fields/match"
    end
  end
end
