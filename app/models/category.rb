# encoding: UTF-8

# Kept apart from tags because the blog treats them differently: a few
# broad, capitalised sections rather than many fine-grained keywords.
class Category
  include Mongoid::Document
  include Taxonomy
end
