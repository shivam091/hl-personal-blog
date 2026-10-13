# encoding: UTF-8

class Filtering
  # A list of named problems rather than values, for when what's worth
  # finding is spread over several fields or compares one with another.
  # Picked from a list like a Select, so it combines with any tab.
  class Condition < Select
    def initialize(name, label:, conditions:, blank_label: "Any")
      @conditions = conditions
      super(name, field: nil, label: label, choices: conditions.transform_values(&:first), blank_label: blank_label)
    end

    def apply(scope, values)
      values[name] ? scope.where(@conditions.fetch(values[name]).last) : scope
    end
  end
end
