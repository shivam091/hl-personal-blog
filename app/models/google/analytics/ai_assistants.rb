# encoding: UTF-8

module Google
  module Analytics
    # Visits from AI chat assistants, which Search Console's Generative AI
    # report can't see since they're not Google's: GA files them as plain
    # referrals, by the assistant's host or the utm_source it tags links with.
    # From landing pages, where a session is counted once, so the visits add
    # up across pages and days.
    class AiAssistants
      # Hosts match with any subdomain; bare names are utm_source tags.
      ASSISTANTS = {
        "ChatGPT" => {hosts: %w[chatgpt.com openai.com], names: %w[chatgpt openai]},
        "Perplexity" => {hosts: %w[perplexity.ai], names: %w[perplexity]},
        "Gemini" => {hosts: %w[gemini.google.com bard.google.com], names: %w[gemini]},
        "Copilot" => {hosts: %w[copilot.microsoft.com copilot.com], names: %w[copilot]},
        "Claude" => {hosts: %w[claude.ai], names: %w[claude]},
        "DeepSeek" => {hosts: %w[deepseek.com], names: %w[deepseek]},
        "Grok" => {hosts: %w[grok.com], names: %w[grok]},
        "Meta AI" => {hosts: %w[meta.ai], names: []},
        "Mistral" => {hosts: %w[chat.mistral.ai], names: []},
        "Poe" => {hosts: %w[poe.com], names: []}
      }.freeze
      ALTERNATIVES = ASSISTANTS.transform_values do |match|
        (match[:hosts].map { |host| "(?:[a-z0-9-]+\\.)*#{Regexp.escape(host)}" } + match[:names].map { |name| Regexp.escape(name) }).join("|")
      end.freeze
      PATTERNS = ALTERNATIVES.transform_values { |alternatives| /\A(?:#{alternatives})\z/i }.freeze
      # One plain pattern for MongoDB, which is given it as it's written here.
      SOURCE = /\A(?:#{ALTERNATIVES.values.join("|")})\z/i

      Figures = Struct.new(:sessions, :engaged_sessions, :key_events) do
        def self.zero = new(0, 0, 0)

        def add(row)
          self.sessions += row.sessions
          self.engaged_sessions += row.engaged_sessions
          self.key_events += row.key_events
          self
        end

        def engagement_rate
          sessions.zero? ? 0.0 : engaged_sessions.fdiv(sessions)
        end
      end

      attr_reader :period

      def self.assistant(source)
        PATTERNS.find { |_, pattern| pattern.match?(source.to_s) }&.first
      end

      def initialize(period)
        @period = period
      end

      def any?(within = period)
        days_with_data(within).any?
      end

      def totals(within = period)
        rows(within).each_with_object(Figures.zero) { |row, sum| sum.add(row) }
      end

      # Only with GA synced from before the period compared with, so a period
      # before the first sync doesn't read as a jump from nothing.
      def previous_totals
        totals(period.previous) if Stat.where(:date.lte => period.previous.from).exists?
      end

      # Nil on days GA hasn't synced, so a gap in the import isn't drawn as
      # nobody coming.
      def daily(within = period)
        by_date = rows(within).each_with_object(Hash.new(0)) { |row, sums| sums[row[:date].to_date] += row.sessions }
        synced = days_with_data(within).to_set
        (within.from..within.to).map { |date| by_date[date] if synced.include?(date) }
      end

      # Busiest first, the assistants nobody came from left out.
      def by_assistant(within = period)
        rows(within).each_with_object(Hash.new { |hash, name| hash[name] = Figures.zero }) do |row, sums|
          name = self.class.assistant(row[:source])
          sums[name].add(row) if name
        end.reject { |_, figures| figures.sessions.zero? }.sort_by { |name, figures| [-figures.sessions, name] }
      end

      # Sessions by the page they landed on.
      def pages(within = period)
        @pages ||= {}
        @pages[within.key] ||= LandingSourceStat.grouped(criteria(within), by: [:page_path]).to_h { |row| [row[:page_path], row.sessions] }
      end

      private

      def rows(within)
        @rows ||= {}
        @rows[within.key] ||= LandingSourceStat.grouped(criteria(within), by: [:date, :source]).to_a
      end

      def criteria(within)
        within.apply(LandingSourceStat.where(source: SOURCE))
      end

      def days_with_data(within)
        @days ||= {}
        @days[within.key] ||= Stat.where(date: within.from..within.to).distinct(:date).map(&:to_date)
      end
    end
  end
end
