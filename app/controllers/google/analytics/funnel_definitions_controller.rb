# encoding: UTF-8

module Google
  module Analytics
    # So a funnel for a new conversion is added where its report is read,
    # rather than waiting on a deploy.
    class FunnelDefinitionsController < ApplicationController
      # Blank rows to fill in, since a funnel is rarely more than a few steps.
      BLANK_STEPS = 2

      before_action :set_definition, only: %i[edit update destroy]

      def index
        @definitions = FunnelDefinition.all_or_defaults
      end

      def new
        @definition = FunnelDefinition.new(position: FunnelDefinition.count)
        add_blank_steps
      end

      def create
        @definition = FunnelDefinition.new(definition_params)

        if @definition.save
          redirect_to google_analytics_funnel_definitions_path, notice: "Added the funnel “#{@definition}”."
        else
          render_with_errors :new
        end
      end

      def edit
        add_blank_steps
      end

      def update
        if @definition.update(definition_params)
          redirect_to google_analytics_funnel_definitions_path, notice: "Updated the funnel “#{@definition}”."
        else
          render_with_errors :edit
        end
      end

      def destroy
        @definition.destroy
        redirect_to google_analytics_funnel_definitions_path, notice: "Deleted the funnel “#{@definition}”.", status: :see_other
      end

      private

      def set_definition
        @definition = FunnelDefinition.find(params[:id])
      end

      def add_blank_steps
        BLANK_STEPS.times { @definition.steps.build }
      end

      # Blank rows again, so a step removed by mistake can be put back
      # while the errors are fixed.
      def render_with_errors(template)
        add_blank_steps
        render template, status: :unprocessable_content
      end

      def definition_params
        params.expect(google_analytics_funnel_definition: [:title, :key, :position, :counted_since,
          steps_attributes: [[:id, :name, :event, :path, :paths_list, :site, :_destroy]]])
      end
    end
  end
end
