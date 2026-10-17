# encoding: UTF-8

module Google
  # Search Console and Analytics reports are all daily figures read as totals
  # over a period, split one way at a time (by page, query, country...), so
  # their pages share one way of listing, exporting and syncing them.
  module DailyReport
    extend ActiveSupport::Concern

    # A breakdown can override the report's figures, collection and GA
    # filters because GA's reports don't share one shape: a landing page
    # report differs from an events report, a page's event count is stored
    # apart from its traffic, and key events are narrower than the rows
    # they're read from.
    # One split by a second dimension names the tab it splits as its parent,
    # so it's picked under that tab's column, as GA's secondary dimension
    # is, rather than crowding the tabs.
    Breakdown = Struct.new(:key, :label, :keys, :headings, :criteria, :search, :default_sort, :metrics, :live_metrics, :chart_metric, :merged, :live_filters, :note,
      :parent, :split_label, keyword_init: true) do
      def model
        criteria.call.klass
      end
    end

    # Some figures are better low (a search position), so the direction a
    # column first sorts in and the colour of a change both follow it.
    # A figure that's mostly zero says more as its change from the period
    # before than as its share of a total. One colour per figure, so it's
    # found across its tile, line and column at a glance. A tile can be
    # named apart from its column, since it holds the whole period's figure.
    Metric = Struct.new(:field, :label, :format, :icon, :lower_is_better, :hint, :row_change, :color, :tile_label, keyword_init: true) do
      def sort_direction
        lower_is_better ? "asc" : "desc"
      end

      # Durations are exported as plain seconds, so they add up in a
      # spreadsheet; the header says so.
      def csv_header
        format == :duration ? "#{label} (s)" : label
      end
    end

    # So rows given GA's own figures still page and export like the grouped
    # scope they replace.
    class LoadedRows
      include Enumerable

      def initialize(rows)
        @rows = rows
      end

      def each(&block)
        return to_enum(:each) unless block

        @rows.each(&block)
      end

      def count(*args, &block)
        args.empty? && !block ? @rows.size : super
      end

      def skip(count)
        self.class.new(@rows.drop(count))
      end

      def limit(count)
        self.class.new(@rows.first(count))
      end

      def to_csv(columns)
        GroupedScope.csv(self, columns)
      end
    end

    # Only searches GA can make the same way, so its figures cover the same
    # rows as the stored ones.
    LIVE_MATCH_TYPES = {Filtering::Contains => "CONTAINS", Filtering::Match => "CONTAINS", Filtering::Select => "EXACT"}.freeze

    # GA gives weekdays and hours as numbers, which sort in time order but
    # read slower than names.
    VALUE_LABELS = {
      day_of_week: ->(value) { Date::DAYNAMES[value.to_i] if value.to_s.match?(/\A[0-6]\z/) },
      hour: ->(value) { "#{value}:00" if value.to_s.match?(/\A\d{2}\z/) },
      hour_at: ->(value) { SearchConsole::HourStat.label(value) if value.respond_to?(:in_time_zone) }
    }.freeze

    class << self
      def value_label(key, value)
        VALUE_LABELS[key]&.call(value) || value
      end
    end

    PATH_SEARCH = Filtering::Match.new(:path, field: :page_path, label: "Page", placeholder: "e.g. /post/ or css-grid")
    # As many as the categorical palette has hues, so no two lines share one.
    CHART_ROWS = ChartsHelper::SHARE_COLORS.size

    # Weeks start on Sunday, as GA's do, so a week here is the week there.
    CHART_BUCKETS = {
      "day" => ->(date) { date },
      "week" => ->(date) { date.beginning_of_week(:sunday) },
      "month" => ->(date) { date.beginning_of_month }
    }.freeze

    Chart = Struct.new(:metric, :dates, :total, :rows, :plotting, keyword_init: true) do
      def plotted?(values)
        rows.any? { |row| row.values == values }
      end
    end
    ChartRow = Struct.new(:values, :label, :value, :daily, keyword_init: true)

    # Kept in the URL, so sorting, paging or another period doesn't lose
    # what's charted. Nothing ticked charts the leading rows, so a report
    # opens with a chart.
    Plotting = Struct.new(:rows, :total, :by, keyword_init: true) do
      class << self
        def read(params, width:)
          rows = begin
            JSON.parse(params[:plot].to_s) if params[:plot].present?
          rescue JSON::ParserError
            nil
          end
          rows = nil unless rows.is_a?(Array) && rows.all? { |row| row.is_a?(Array) && row.size == width && row.all? { |value| value.nil? || value.is_a?(String) } }
          new(
            rows: rows&.uniq&.first(CHART_ROWS),
            total: params[:plot_total] != "0",
            by: params[:chart_by].presence_in(CHART_BUCKETS.keys) || "day"
          )
        end
      end

      def query
        {plot: (rows.to_json if rows), plot_total: ("0" unless total), chart_by: (by unless by == "day")}.compact
      end
    end

    # Stored traffic holds every event together, so a figure narrowed to one
    # event has to be asked of GA.
    EventFilter = Struct.new(:field, :param, :metric, :key_events_only, keyword_init: true)
    EVENT_FILTERS = [
      EventFilter.new(field: :event_count, param: :event, metric: "eventCount"),
      EventFilter.new(field: :key_events, param: :key_event, metric: "keyEvents", key_events_only: true)
    ].freeze

    # Kept in the URL like a search, so sorting, paging or another breakdown
    # keeps the event a figure is narrowed to.
    EventChoice = Struct.new(:filters, :choices, :events, keyword_init: true) do
      class << self
        def read(params, filters:, choices:)
          new(
            filters: filters,
            choices: choices,
            events: filters.to_h { |filter| [filter.field, params[filter.param].presence_in(choices.fetch(filter.field))] }.compact
          )
        end
      end

      def query
        filters.to_h { |filter| [filter.param, events[filter.field]] }.compact
      end
    end

    # The period compared with is read bucket for bucket against this one,
    # so its line runs under the same dates.
    # Figures stored by the hour fit none of the buckets that can be picked.
    Trend = Struct.new(:dates, :values, :previous, :selection, :per, keyword_init: true) do
      def per
        self[:per] || selection.by
      end
    end

    # Kept in the URL, so sorting, paging or another period doesn't lose
    # what's charted. Clicks and impressions first, as in Search Console, and
    # in the tiles' order however they were ticked, so one choice has one URL.
    TrendSelection = Struct.new(:fields, :by, :available, keyword_init: true) do
      class << self
        def read(params, available:)
          asked = params[:trend].to_s.split(",")
          fields = params[:trend].nil? ? available.first(2) : available.select { |field| asked.include?(field.to_s) }
          new(fields: fields, by: params[:chart_by].presence_in(CHART_BUCKETS.keys) || "day", available: available)
        end
      end

      def query
        {trend: (fields.join(",") unless fields == available.first(2)), chart_by: (by unless by == "day")}.compact
      end
    end

    included do
      before_action :set_breakdown
      helper_method :breakdown_query, :sync_dialog_locals, :report_metrics, :figure_metrics, :report_breakdowns, :sync_kind, :report_shares?,
                    :unanswerable_search, :event_filters, :table_metrics, :table_columns, :unsettled_from
    end

    class_methods do
      # Every figure any breakdown shows, once, so one layout covers the
      # whole report. A breakdown's own columns stand as one, since they
      # differ from tab to tab and name each row.
      def layout_columns
        metrics = [*self::METRICS, *self::BREAKDOWNS.values.flat_map { |breakdown| Array(breakdown.metrics) }].uniq(&:field)
        {"breakdown" => {label: "Breakdown", required: true}}
          .merge(metrics.to_h { |metric| [metric.field.to_s, {label: metric.label, sort: metric.sort_direction, align: "right"}] })
      end
    end

    def index
      load_report

      respond_to do |format|
        format.html { load_page }
        format.csv do
          daily = params[:export] == "daily"
          send_csv daily ? @filtered.klass.to_csv(@filtered.order(date: :desc)) : @rows_scope.to_csv(export_columns),
            filename: "#{self.class::EXPORT_NAME}-#{@breakdown.key}#{"-daily" if daily}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
            detail: "#{@breakdown.label}#{", day by day" if daily}, #{@period}"
        end
      end
    end

    def sync
      @sync_range = SyncRange.new(params.expect(google_sync_range: %i[from to]).merge(earliest: sync_earliest))

      if @sync_range.valid?
        SyncRequest.enqueue(sync_kind, from_date: @sync_range.from, to_date: @sync_range.to)
        redirect_to url_for(action: :index),
          notice: "Syncing #{helpers.pluralize(@sync_range.days, "day")} (#{l(@sync_range.from)} to #{l(@sync_range.to)}) " \
            "from #{self.class::SYNC_SOURCE} in the background. Refresh in a moment to see the new figures."
      else
        respond_to do |format|
          # Only the dialog is redrawn, so the report behind it stays exactly
          # as it was while the dates are fixed.
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace("sync-dialog", partial: "google/shared/sync_dialog", locals: sync_dialog_locals),
              status: :unprocessable_content
          end
          format.html do
            load_report
            load_page
            render :index, status: :unprocessable_content
          end
        end
      end
    end

    private

    def report_metrics
      @breakdown.metrics || self.class::METRICS
    end

    # Named with the event they're narrowed to, so a tile or an export
    # doesn't read as every event's.
    def figure_metrics
      report_metrics.map do |metric|
        event = @narrowed && @event_choice.events[metric.field]
        event ? metric.dup.tap { |narrowed| narrowed.label = "#{metric.label} (#{event})" } : metric
      end
    end

    # Only for traffic rows, which hold every event together; a row of
    # events is already one kind of event.
    def event_filters
      @event_filters ||=
        if self.class.const_defined?(:EVENT_FILTERING) && self.class::EVENT_FILTERING && @breakdown.model.include?(Analytics::Traffic)
          fields = report_metrics.map(&:field)
          EVENT_FILTERS.select { |filter| fields.include?(filter.field) }
        else
          []
        end
    end

    def sync_kind
      self.class::SYNC_KIND
    end

    def report_breakdowns
      self.class::BREAKDOWNS.values
    end

    # Only the figures ticked on the trend, as in Search Console, where the
    # table follows the chart; every figure while none is ticked, so the
    # table never goes empty.
    def table_metrics
      metrics = laid_out_metrics
      follows = self.class.const_defined?(:TABLE_FOLLOWS_TREND) && self.class::TABLE_FOLLOWS_TREND
      return metrics unless follows && @trend&.selection&.fields&.any?

      metrics.select { |metric| !metric.color || @trend.selection.fields.include?(metric.field) }
    end

    # The figures in the saved order, less the hidden ones; a figure this
    # breakdown doesn't have is skipped rather than drawn empty. Until one
    # is saved, each breakdown keeps its own order, as GA's reports do.
    def laid_out_metrics
      return report_metrics unless @layout&.customized?

      metrics = report_metrics.index_by { |metric| metric.field.to_s }
      @layout.visible_columns.filter_map { |column| metrics[column.key] }
    end

    # The figures with :breakdown where the layout puts the breakdown's own
    # columns.
    def table_columns
      return [:breakdown, *table_metrics] unless @layout&.customized?

      before = @layout.visible_columns.take_while { |column| column.key != "breakdown" }.map(&:key)
      leading, trailing = table_metrics.partition { |metric| before.include?(metric.field.to_s) }
      [*leading, :breakdown, *trailing]
    end

    def list_layout
      ListLayout.find(self.class::LIST_LAYOUT) if self.class.const_defined?(:LIST_LAYOUT)
    end

    # A share only means something for counts that add up to the total,
    # which not every report's figures do.
    def report_shares?
      self.class.const_defined?(:SHOW_SHARES) && self.class::SHOW_SHARES
    end

    # So one page can be followed from its totals to its queries or
    # countries; other searches belong to the breakdown they were made in.
    def breakdown_query
      {**@period.query, **(@filtering.tabs ? {@filtering.tabs.name => @filtering.tab} : {}), **@filtering.query_for(shared_search_fields),
       **(@trend&.selection&.query || {}), **(@event_choice&.query || {})}.compact
    end

    # So a search the stored figures can't answer says why, rather than
    # reading as one with no results.
    def unanswerable_search
      nil
    end

    # The first day the source may still revise, so the charts can say its
    # figures aren't final; nil where the source doesn't say.
    def unsettled_from
      nil
    end

    # Kept on switching breakdowns, since they mean the same on each; a
    # breakdown's own search wouldn't.
    def shared_search_fields
      [PATH_SEARCH]
    end

    # So an unknown breakdown is a 404 rather than a 500.
    def set_breakdown
      @breakdown = self.class::BREAKDOWNS[params[:breakdown]]
      raise ActionController::RoutingError, "No #{params[:breakdown]} breakdown" unless @breakdown
    end

    def sync_dialog_locals
      {sync_range: @sync_range, url: url_for(action: :sync, only_path: true), source: self.class::SYNC_SOURCE}
    end

    def load_report
      @layout = list_layout
      @period = Period.new(params)
      @filtering = Filtering.new(params, fields: [*shared_search_fields, *@breakdown.search], tabs: tabs)
      # Figures are what's being compared, so they sort first; a breakdown's
      # own fields sort alphabetically.
      sorts = report_metrics.to_h { |metric| [metric.field.to_s, metric.sort_direction] }
        .merge(@breakdown.keys.to_h { |key| [key.to_s, "asc"] })
      sorts = @breakdown.default_sort.merge(sorts.except(*@breakdown.default_sort.keys)) if @breakdown.default_sort
      # Only a sort the admin saved, so a breakdown keeps its own default
      # otherwise; one on a figure this breakdown lacks falls back to it.
      default = @layout.default_sort if @layout&.setting&.sort
      @sorting = Sorting.new(params, columns: sorts, tiebreaker: @breakdown.keys, default: default)
      @filtered = @filtering.apply(@period.apply(breakdown_criteria))
      @rows_scope = @sorting.apply(@filtered.klass.grouped(@filtered, by: @breakdown.keys))
      @live = live_figures(@period) if live_metrics
      @merged = merged_figures(@period) if @breakdown.merged
      @event_choice = read_event_choice if event_filters.any?
      @narrowed = narrowed_figures(@period) if @event_choice&.events&.any?
      @rows_scope = LoadedRows.new(sort_rows(merge_figures(@rows_scope))) if @live || @merged || @narrowed
    end

    def load_page
      @pagination = @layout ? @layout.pagination(@rows_scope, params) : Pagination.new(@rows_scope, params)
      # Loaded once, since a grouped scope re-runs its aggregation each time it's read.
      @rows = @pagination.records.to_a
      @totals = totals_for(@period)
      @totals = @totals.merge(@live.total) if @live
      @totals = @totals.merge(@merged[:total]) if @merged
      @totals = narrow(@totals, @narrowed.total) if @narrowed
      # Only once a comparison is picked, since a live figure's costs a GA
      # call; and not with a period from before the first sync, which would
      # read as a jump from zero.
      if @period.compare? && @filtered.klass.where(:date.lte => @period.previous.from).exists?
        @previous_totals = previous_totals
        @previous_rows = previous_rows
      end
      @tab_counts = tab_counts(@filtering.searched(@period.apply(breakdown_criteria))) if tabs
      @chart = load_chart(chart_metric, Plotting.read(params, width: @breakdown.keys.size)) if chart_metric && @pagination.total_count.positive?
      trend_metrics = report_metrics.select(&:color)
      @trend = load_trend(TrendSelection.read(params, available: trend_metrics.map(&:field))) if trend_metrics.any?
      @sync_range ||= SyncRange.new(earliest: sync_earliest)
    end

    def breakdown_criteria
      @breakdown.criteria.call
    end

    # GA's own figures against stored ones would be a change made up of the
    # two ways of counting, so without the earlier period's there's none.
    def previous_totals
      totals = totals_for(@period.previous)
      if @breakdown.merged
        @previous_merged = merged_figures(@period.previous)
        totals = totals.merge(@previous_merged[:total])
      end
      if @narrowed
        @previous_narrowed = narrowed_figures(@period.previous)
        return unless @previous_narrowed

        totals = narrow(totals, @previous_narrowed.total)
      end
      return totals unless @live

      @previous_live = live_figures(@period.previous)
      totals.merge(@previous_live.total) if @previous_live
    end

    # Searched the same way as the rows they join, so a page's figures are
    # for the same days and pages.
    def merged_figures(period)
      keys = @breakdown.keys
      fields = @breakdown.merged[:fields]
      criteria = @filtering.apply(period.apply(@breakdown.merged[:criteria].call))
      grouped = criteria.klass.grouped(criteria, by: keys)
      totals = grouped.totals
      {rows: grouped.to_h { |row| [keys.map { |key| row[key] }, fields.index_with { |field| row.value(field) }] },
       total: fields.index_with { |field| totals.value(field) }}
    end

    # Only for this page's rows. GA's figures come from the one call the
    # totals already made, and without them there's no change to show, as
    # for the totals.
    def previous_rows
      return if @narrowed && !@previous_narrowed
      return if @live && !@previous_live

      keys = @breakdown.keys
      shown = @rows.map { |row| keys.map { |key| row[key] } }
      return {} if shown.empty?

      criteria = previous_rows_criteria(@period.previous).any_of(*shown.map { |values| keys.zip(values).to_h })
      criteria.klass.grouped(criteria, by: keys).to_h do |row|
        values = keys.map { |key| row[key] }
        row = row.merge(@previous_live.rows.fetch(values) { live_fields.index_with(0) }) if @previous_live
        row = row.merge(@previous_merged[:rows].fetch(values) { @breakdown.merged[:fields].index_with(0) }) if @previous_merged
        row = narrow(row, narrowed_row(@previous_narrowed, values)) if @previous_narrowed
        [values, row]
      end
    end

    def previous_rows_criteria(period)
      totals_criteria(period)
    end

    def live_metrics
      @breakdown.live_metrics || (self.class::LIVE_METRICS if self.class.const_defined?(:LIVE_METRICS))
    end

    # So GA being unavailable still leaves the summed figures to read, and
    # says why they run high.
    def live_figures(period)
      dimensions = Analytics::SyncService.dimensions_for(@breakdown.model)
      filters = live_filters(dimensions)
      raise Analytics::LiveFigures::Unavailable, "this search can't be asked of Google Analytics" unless filters

      asked = @breakdown.keys.index_with { |key| dimensions.fetch(key) }
      live = Analytics::LiveFigures.call(from: period.from, to: period.to, dimensions: asked, metrics: live_metrics, filters: filters)
      live_extras.reduce(live) do |result, extra|
        found = Analytics::LiveFigures.call(from: period.from, to: period.to, dimensions: asked, metrics: extra[:metrics],
          filters: filters + extra[:filters])
        zero = extra[:metrics].keys.index_with(0)
        Analytics::LiveFigures::Result.new(rows: result.rows.to_h { |values, figures| [values, figures.merge(found.rows.fetch(values, zero))] },
          total: result.total.merge(found.total))
      end
    rescue Analytics::LiveFigures::Unavailable => e
      @live_error = e.message if period.equal?(@period)
      nil
    end

    # Only those the report shows, since each is a GA call of its own.
    def live_extras
      shown = report_metrics.map(&:field)
      Analytics::SyncService.extras_for(@breakdown.model).select { |extra| extra[:metrics].keys.intersect?(shown) }
    end

    def live_fields
      live_metrics.keys + live_extras.flat_map { |extra| extra[:metrics].keys }
    end

    def live_filters(dimensions)
      return if @filtering.tab.present?

      fixed = Analytics::SyncService.filters_for(@breakdown.model) + (@breakdown.live_filters || [])
      fixed + @filtering.fields.filter_map do |field|
        value = @filtering.values[field.name]
        next unless value

        dimension = dimensions[field.field]
        match_type = field.is_a?(Filtering::Match) && @filtering.values[field.match_param] ? "EXACT" : LIVE_MATCH_TYPES[field.class]
        return nil unless dimension && match_type

        [dimension, match_type, value]
      end
    end

    def read_event_choice
      events = @period.apply(Analytics::EventStat.all)
      choices = event_filters.to_h do |filter|
        [filter.field, (filter.key_events_only ? events.where(:key_events.gt => 0) : events).distinct(:event_name).sort]
      end
      EventChoice.read(params, filters: event_filters, choices: choices)
    end

    # Each asked apart, since each figure can be narrowed to its own event.
    # So GA being unavailable still leaves figures to read, and says why they
    # count every event.
    def narrowed_figures(period)
      dimensions = Analytics::SyncService.dimensions_for(@breakdown.model)
      filters = live_filters(dimensions)
      raise Analytics::LiveFigures::Unavailable, "this search can't be asked of Google Analytics" unless filters

      results = @event_choice.filters.filter_map do |filter|
        event = @event_choice.events[filter.field]
        next unless event

        Analytics::LiveFigures.call(from: period.from, to: period.to, dimensions: @breakdown.keys.index_with { |key| dimensions.fetch(key) },
          metrics: {filter.field => filter.metric}, filters: [*filters, ["eventName", "EXACT", event]])
      end
      Analytics::LiveFigures::Result.new(rows: results.map(&:rows).reduce { |all, rows| all.merge(rows) { |_, a, b| a.merge(b) } },
        total: results.map(&:total).reduce(:merge))
    rescue Analytics::LiveFigures::Unavailable => e
      @event_error = e.message if period.equal?(@period)
      nil
    end

    # Events per session stays over every event, as in GA, where an event
    # chosen for Event count narrows only that column.
    def narrow(row, figures)
      row.merge(every_event_count: row.value(:event_count), **figures)
    end

    # A row GA has nothing for had none of the chosen event.
    def narrowed_row(narrowed, values)
      narrowed.total.keys.index_with(0).merge(narrowed.rows.fetch(values, {}))
    end

    # A row GA, or the merged collection, has nothing for had none of
    # those figures.
    def merge_figures(rows)
      rows.map do |row|
        values = @breakdown.keys.map { |key| row[key] }
        row = row.merge(@live.rows.fetch(values) { live_fields.index_with(0) }) if @live
        row = row.merge(@merged[:rows].fetch(values) { @breakdown.merged[:fields].index_with(0) }) if @merged
        row = narrow(row, narrowed_row(@narrowed, values)) if @narrowed
        row
      end
    end

    # Sorted again here, since the database sorted by the summed figures.
    def sort_rows(rows)
      column = @sorting.column
      tiebreakers = Array(@sorting.tiebreaker)
      rows.sort do |a, b|
        order = (a.value(column) <=> b.value(column)) || 0
        order = -order if @sorting.direction == "desc"
        order.nonzero? || tiebreakers.lazy.map { |key| (a.value(key) <=> b.value(key)) || 0 }.find(&:nonzero?) || 0
      end
    end

    def totals_for(period)
      criteria = totals_criteria(period)
      criteria.klass.grouped(criteria, by: @breakdown.keys).totals
    end

    def totals_criteria(period)
      @filtering.apply(period.apply(breakdown_criteria))
    end

    def export_columns
      @breakdown.headings.zip(@breakdown.keys).to_h.merge(figure_metrics.to_h { |metric| [metric.csv_header, metric.field] })
    end

    def chart_metric
      field = @breakdown.chart_metric || (self.class::CHART_METRIC if self.class.const_defined?(:CHART_METRIC))
      report_metrics.find { |metric| metric.field == field } if field
    end

    # Unless rows are ticked, the leading rows by the charted figure whatever
    # the table is sorted by, so the charts don't change with a click on a
    # column. A day with no rows at all is left out rather than drawn as
    # zero, since it may not have been synced.
    def load_chart(metric, plotting)
      keys = @breakdown.keys
      field = metric.field
      model = @breakdown.model
      matching = ->(rows) { @filtered.any_of(*rows.map { |values| keys.zip(values).to_h }) }
      top =
        if plotting.rows&.empty? then []
        else
          scope = plotting.rows ? matching.(plotting.rows) : @filtered
          model.grouped(scope, by: keys).order({field => :desc, **keys.to_h { |key| [key, :asc] }}).limit(CHART_ROWS).to_a
        end
      tops = top.map { |row| keys.map { |key| row[key] } }
      daily = tops.empty? ? {} : model.grouped(matching.(tops), by: [:date, *keys])
        .to_h { |row| [[row[:date].to_date, *keys.map { |key| row[key] }], row.value(field)] }
      total = model.grouped(@filtered, by: [:date]).to_h { |row| [row[:date].to_date, row.value(field)] }
      dates = (@period.from..@period.to).to_a
      buckets = dates.each_index.group_by { |index| CHART_BUCKETS.fetch(plotting.by).(dates[index]) }
      # A week or month with no stored day at all stays a gap, like a day.
      bucketed = ->(values) { buckets.values.map { |indexes| values.values_at(*indexes).compact.then { |known| known.sum if known.any? } } }

      Chart.new(metric: metric, dates: buckets.keys, total: bucketed.(dates.map { |date| total[date] }), plotting: plotting,
        rows: top.zip(tops).map do |row, values|
          ChartRow.new(
            values: values,
            label: keys.zip(values).map { |key, value| DailyReport.value_label(key, value.presence || "(not set)") }.join(" · "),
            value: row.value(field),
            daily: bucketed.(dates.map { |date| total.key?(date) ? daily.fetch([date, *values], 0) : nil })
          )
        end)
    end

    # Read from the totals' rows, so the lines add up to the totals. The
    # period compared with only once it was synced, as for the totals.
    def load_trend(selection)
      current = trend_values(@period, selection)
      previous = trend_values(@period.previous, selection) if @previous_totals
      Trend.new(
        dates: current.keys,
        selection: selection,
        values: selection.available.index_with { |field| current.values.map { |row| row&.value(field) } },
        previous: (selection.available.index_with { |field| previous.values.map { |row| row&.value(field) }.first(current.size) } if previous)
      )
    end

    # Nil rather than zero where nothing was stored, since it may not have
    # been synced.
    def trend_values(period, selection)
      starts = (period.from..period.to).map { |date| CHART_BUCKETS.fetch(selection.by).(date) }.uniq
      criteria = totals_criteria(period)
      rows = criteria.klass
               .grouped(criteria, by: [])
               .bucketed(:date, starts: starts.map { |date| utc(date) }, before: utc(period.to + 1))
               .transform_keys(&:to_date)
      starts.index_with { |start| rows[start] }
    end

    # Days are stored as midnight UTC, so that's where a bucket is cut.
    def utc(date)
      Time.utc(date.year, date.month, date.day)
    end

    def tabs
      self.class::TABS if self.class.const_defined?(:TABS)
    end

    def sync_earliest
      nil
    end
  end
end
