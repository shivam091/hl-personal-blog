# encoding: UTF-8

class Filtering
  # For fields with a short, known set of values, where picking from a list
  # is faster than typing and can't produce a value that matches nothing.
  # Choices may be a hash of value => label, so a stored key can read as a
  # name without the URL carrying the name.
  class Select
    attr_reader :name, :field, :label, :choices, :blank_label

    def initialize(name, field:, label:, choices:, blank_label: "Any")
      @name, @field, @label, @choices, @blank_label = name, field, label, choices, blank_label
    end

    def read(params)
      {name => params[name].presence_in(values)}
    end

    def apply(scope, values)
      values[name] ? scope.where(field => values[name]) : scope
    end

    def chips(values)
      values[name] ? [["#{label}: #{choice_label(values[name])}", name]] : []
    end

    # Nothing for a value the list doesn't offer, since it would be dropped.
    def exact_query(value)
      {name => value} if values.include?(value)
    end

    def values
      choices.is_a?(Hash) ? choices.keys : choices
    end

    def options
      choices.is_a?(Hash) ? choices.map { |value, label| [label, value] } : choices
    end

    def to_partial_path
      "shared/filtering/fields/select"
    end

    private

    def choice_label(value)
      choices.is_a?(Hash) ? choices.fetch(value) : value
    end
  end
end
