# encoding: UTF-8

class Filtering
  # Lets the reader search by a field the records only hold through a
  # reference, such as a URL kept on another collection, since an id means
  # nothing to a person.
  class RelatedContains < Contains
    attr_reader :model, :model_field

    def initialize(name, field:, label:, model:, model_field:, placeholder: nil)
      super(name, field: field, label: label, placeholder: placeholder)
      @model, @model_field = model, model_field
    end

    def apply(scope, values)
      return scope unless values[name]

      scope.where(field.in => model.where(model_field => /#{Regexp.escape(values[name])}/i).pluck(:_id))
    end
  end
end
