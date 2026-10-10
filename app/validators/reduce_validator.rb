# encoding: UTF-8

# Keeps only the first error on an attribute, so a blank value reads as
# "can't be blank" rather than also "is too short". Must come last, since it
# only sees errors already added.
class ReduceValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, _value)
    first = record.errors.where(attribute).first
    record.errors.objects.reject! { |error| error.attribute == attribute && !error.equal?(first) }
  end
end
