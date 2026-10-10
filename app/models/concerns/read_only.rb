# encoding: UTF-8

# Guards collections the blog frontend owns from accidental writes here,
# since this app shares the live database. Included after Mongoid::Document
# because Mongoid's own readonly? would otherwise win.
module ReadOnly
  def readonly?
    true
  end
end
