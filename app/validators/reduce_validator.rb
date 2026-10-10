# encoding: UTF-8

# Keeps only the first error on an attribute, so a blank value reads as
# "can't be blank" rather than also "is too short". Give it last, since it
# only sees errors already added and validators run in the order given.
#
#   validates :name, presence: true, length: {in: 2..40}, reduce: true
class ReduceValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, _value)
    first = record.errors.where(attribute).first
    record.errors.objects.reject! { |error| error.attribute == attribute && !error.equal?(first) }
  end
end
