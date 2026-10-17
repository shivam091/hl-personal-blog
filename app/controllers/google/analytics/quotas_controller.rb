# encoding: UTF-8

module Google
  module Analytics
    # Exists so a sync failing on GA's quota is seen coming, rather than found
    # afterwards in the sync requests.
    class QuotasController < ApplicationController
      def show
        @quotas = Quota.all.index_by(&:category)
      end
    end
  end
end
