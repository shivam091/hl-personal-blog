# encoding: UTF-8

module Google
  module Analytics
    # Copied so GA traffic can sit beside Search Console data and the blog's
    # own page views without opening GA.
    class Stat
      include Mongoid::Document
      include Traffic

      breakdown
    end
  end
end
