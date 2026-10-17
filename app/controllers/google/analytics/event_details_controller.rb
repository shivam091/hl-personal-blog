# encoding: UTF-8

module Google
  module Analytics
    # As GA opens an event from its Events report: one event's figures, over
    # time, live, and by page and country, so it can be read on its own.
    class EventDetailsController < ApplicationController
      METRICS = EngagementController::METRICS
      # Every figure narrowed to the event, sessions included, so Events per
      # session is over the sessions that had it, as on GA's event page.
      LIVE_METRICS = EngagementController::LIVE_METRICS
      PAGES_SHOWN = 10
      COUNTRIES_SHOWN = 10

      def show
        @event_name = params[:event_name]
        @period = Period.new(params)
        @totals = totals_for(@period)
        # Only once a comparison is picked, as on every report.
        compared = @period.compare? && EventStat.where(:date.lte => @period.previous.from).exists?
        @previous_totals = totals_for(@period.previous) if compared
        @event_counts = daily_event_counts(@period)
        @previous_event_counts = daily_event_counts(@period.previous) if compared
        @pages = grouped(@period, by: :page_path)
        @countries = live_figures(@period, dimensions: {country: "countryId"}, metrics: {event_count: "eventCount"})
          &.rows&.to_h { |(country), figures| [country, figures[:event_count]] }
        @events_per_session = daily_events_per_session(@period)
        @previous_events_per_session = daily_events_per_session(@period.previous) if @events_per_session && compared
        @realtime = RealtimeService.event(@event_name)
      end

      private

      def stored(period)
        period.apply(EventStat.where(event_name: @event_name))
      end

      # GA's own users and sessions when it can be asked, since a reader
      # counts once over the period; the earlier period's change is left
      # out without them, rather than set against summed figures.
      def totals_for(period)
        totals = EventStat.grouped(stored(period), by: []).totals
        live = live_figures(period, dimensions: {}, metrics: LIVE_METRICS)
        return totals.merge(live.total) if live

        totals if period.equal?(@period)
      end

      def grouped(period, by:)
        EventStat.grouped(stored(period), by: [by]).to_h { |row| [row[by], row.event_count] }
      end

      # A day synced without the event is a zero; one never synced is a gap.
      def daily_event_counts(period)
        synced = period.apply(EventStat.all).distinct(:date).map(&:to_date).to_set
        counts = grouped(period, by: :date).transform_keys(&:to_date)
        dates(period).map { |date| counts.fetch(date, 0) if synced.include?(date) }
      end

      # Asked of GA a day at a time, since a session can't be added up from
      # the stored days.
      def daily_events_per_session(period)
        figures = live_figures(period, dimensions: {date: "date"}, metrics: {event_count: "eventCount", sessions: "sessions"})
        return unless figures

        dates(period).map do |date|
          day = figures.rows.fetch([date.strftime("%Y%m%d")], {})
          day[:sessions].to_i.zero? ? 0.0 : day[:event_count].to_i.fdiv(day[:sessions])
        end
      end

      def dates(period)
        (period.from..period.to).to_a
      end

      # So GA being unavailable still leaves the stored figures to read, and
      # says why the users run high and the live cards are missing.
      def live_figures(period, dimensions:, metrics:)
        LiveFigures.call(from: period.from, to: period.to, dimensions: dimensions, metrics: metrics,
          filters: [["eventName", "EXACT", @event_name]])
      rescue LiveFigures::Unavailable => e
        @live_error ||= e.message if period.equal?(@period)
        nil
      end
    end
  end
end
