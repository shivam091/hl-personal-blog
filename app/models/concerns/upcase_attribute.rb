# encoding: UTF-8

# Keeps values that are case-insensitive by nature (HTTP methods, codes) in
# one canonical case, so filtering and grouping by them can't miss records.
module UpcaseAttribute
  extend ActiveSupport::Concern

  class_methods do
    def upcase_attributes!(*attrs)
      attributes_to_upcase.concat(attrs)
    end

    def attributes_to_upcase
      @attributes_to_upcase ||= []
    end
  end

  included do
    before_validation :upcase_attributes!
  end

  # Reassigned rather than upcased in place: the value may be frozen.
  def upcase_attributes!
    self.class.attributes_to_upcase.each do |attr|
      self[attr] = self[attr].upcase if self[attr].respond_to?(:upcase)
    end
  end
end
