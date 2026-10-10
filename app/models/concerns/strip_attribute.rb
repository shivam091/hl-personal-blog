# encoding: UTF-8

# Stray whitespace from forms and CSVs would otherwise make equal values
# look different to validations, lookups, and uniqueness checks.
module StripAttribute
  extend ActiveSupport::Concern

  class_methods do
    def strip_attributes!(*attrs)
      attributes_to_strip.concat(attrs)
    end

    def attributes_to_strip
      @attributes_to_strip ||= []
    end
  end

  included do
    before_validation :strip_attributes!
  end

  # Reassigned rather than stripped in place: the value may be frozen.
  def strip_attributes!
    self.class.attributes_to_strip.each do |attr|
      self[attr] = self[attr].strip if self[attr].respond_to?(:strip)
    end
  end
end
