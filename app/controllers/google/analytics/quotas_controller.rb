# encoding: UTF-8

module Google
  module Analytics
    class QuotasController < ApplicationController
      def show
        # A kind no longer asked for may still be stored.
        @quotas = Quota.where(:category.in => Quota::CATEGORIES.keys).index_by(&:category)
      end
    end
  end
end
