# encoding: UTF-8

class Filtering
  # Lets the reader filter by name although records store another
  # collection's ids, since ids mean nothing to a person. Choices aren't
  # fixed at boot, so names added by a sync show up without a restart.
  class Reference
    attr_reader :name, :field, :label, :model, :blank_label

    def initialize(name, field:, label:, model:, blank_label: "Any")
      @name, @field, @label, @model, @blank_label = name, field, label, model, blank_label
    end

    def read(params)
      {name => params[name].to_s.strip.presence}
    end

    # A name that matches nothing shows nothing, rather than silently
    # showing everything.
    def apply(scope, values)
      return scope unless values[name]

      id = model.where(name: values[name]).pick(:_id)
      id ? scope.where(field => id) : scope.none
    end

    def chips(values)
      values[name] ? [["#{label}: #{values[name]}", name]] : []
    end

    def choices
      model.names
    end
    alias_method :options, :choices

    def to_partial_path
      "shared/filtering/fields/select"
    end
  end
end
