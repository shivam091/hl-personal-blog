# encoding: UTF-8

# Lets the generic list classes be tested on their own, so their specs
# don't break when an app model changes.
class ListSpecDocument
  include Mongoid::Document

  field :url, type: String
  field :indexed, type: Boolean
  field :last_modified_at, type: Time
end
