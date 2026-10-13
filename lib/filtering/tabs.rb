# encoding: UTF-8

class Filtering
  # For filters with a few exclusive values, where one-click tabs with
  # counts beat a form field.
  class Tabs
    attr_reader :name, :field, :label, :choices, :all_label

    def initialize(name, field:, label:, choices:, all_label: "All")
      @name, @field, @label, @choices, @all_label = name, field, label, choices, all_label
    end

    def read(params)
      params[name].presence_in(choices.keys)
    end

    def apply(scope, key)
      key ? scope.where(field => choices.fetch(key).last) : scope
    end

    # An "All" tab is always offered so the filter can be cleared.
    def options
      [[all_label, nil]] + choices.map { |key, (label, _value)| [label, key] }
    end

    def counts(scope)
      options.to_h { |_label, key| [key, apply(scope, key).count] }
    end
  end
end
