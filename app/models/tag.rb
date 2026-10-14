# encoding: UTF-8

# Its own collection so each tag is stored once, however many entries use
# it, and the list can offer every tag to filter by.
class Tag
  include Mongoid::Document
  include Taxonomy
end
