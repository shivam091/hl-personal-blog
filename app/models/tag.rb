# encoding: UTF-8

# Its own collection so each tag is stored once, however many entries use
# it.
class Tag
  include Mongoid::Document
  include Taxonomy
end
