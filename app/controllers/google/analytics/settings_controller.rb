# encoding: UTF-8

module Google
  module Analytics
    class SettingsController < ApplicationController
      def show
        @result = SettingsService.call
      end

      # Inline rather than queued: it's one quick write, and whether GA took
      # it is what the page is opened to see.
      def register_dimension
        parameter = params[:parameter_name].to_s
        unless CustomDimensionService.known?(parameter)
          return redirect_to google_analytics_settings_path, alert: "Unknown custom dimension or metric.", status: :see_other
        end

        kind = SettingsService::EXPECTED_CUSTOM_METRICS.key?(parameter) ? "metric" : "dimension"
        result = CustomDimensionService.call(parameter)
        if result.errors.any?
          redirect_to google_analytics_settings_path, alert: result.errors.to_sentence, status: :see_other
        else
          redirect_to google_analytics_settings_path, notice: "Registered #{parameter} as a custom #{kind}. GA reports it from now on, not for past events.",
            status: :see_other
        end
      end

      # For entries a failed feed sync left unmarked, since each new one is
      # otherwise marked after the sync that brings it in.
      def annotate
        SyncRequest.enqueue("analytics_annotations")
        redirect_to google_analytics_settings_path, status: :see_other,
          notice: "Marking the last #{AnnotationService::LOOKBACK_DAYS} days' entries on GA's charts in the background. Refresh in a moment to see them."
      end
    end
  end
end
