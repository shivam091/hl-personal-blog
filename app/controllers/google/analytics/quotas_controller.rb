# encoding: UTF-8

module Google
  module Analytics
    class QuotasController < ApplicationController
      def show
        @quotas = Quota.all.index_by(&:category)
      end
    end
  end
end
