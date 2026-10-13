# encoding: UTF-8

require "csv"

# Daily figures are stored a row per day but read as totals over a period;
# grouping in the database keeps a long period from being loaded into
# memory just to be added up.
class GroupedScope
  include Enumerable

  # Dimensions differ per breakdown, so they get no fixed readers.
  class Row
    def initialize(document)
      @document = document
    end

    def [](field)
      @document[field.to_s]
    end

    def value(field)
      respond_to?(field) ? public_send(field) : self[field]
    end

    def merge(values)
      self.class.new(@document.merge(values.transform_keys(&:to_s)))
    end
  end

  # A rate or an average can't be added up across days, so it's derived
  # from the summed counts instead.
  def initialize(criteria, keys:, sums:, row_class:, derived: {}, stages: {})
    @criteria = criteria
    @keys = keys
    @sums = sums
    @derived = derived
    @row_class = row_class
    @stages = stages
  end

  def order(columns)
    with(sort: columns.to_h { |column, direction| [column.to_s, direction.to_s == "desc" ? -1 : 1] })
  end

  def skip(count)
    with(skip: count)
  end

  def limit(count)
    with(limit: count)
  end

  def count
    result = aggregate([*grouping, {"$count" => "count"}]).first
    result ? result["count"] : 0
  end

  def each(&block)
    return to_enum(:each) unless block

    stages = grouping
    stages << {"$sort" => @stages[:sort]} if @stages[:sort]
    stages << {"$skip" => @stages[:skip]} if @stages[:skip].to_i.positive?
    stages << {"$limit" => @stages[:limit]} if @stages[:limit]
    aggregate(stages).each { |document| yield @row_class.new(document) }
  end

  # Headline figures must cover every group, not just the page shown.
  def totals
    stages = [{"$match" => @criteria.selector}, {"$group" => {"_id" => nil, **sum_stage}}]
    stages << {"$addFields" => @derived} if @derived.any?
    @row_class.new(aggregate(stages).first || {})
  end

  # So a rate or an average over each week or month is worked out from its
  # own counts, as over a whole period. Empty buckets are left out so an
  # unsynced stretch reads as a gap, not as zero.
  def bucketed(field, starts:, before:)
    stages = [
      {"$match" => @criteria.selector},
      {"$bucket" => {"groupBy" => "$#{field}", "boundaries" => [*starts, before], "default" => "outside", "output" => sum_stage}}
    ]
    stages << {"$addFields" => @derived} if @derived.any?
    aggregate(stages).reject { |document| document["_id"] == "outside" }.to_h { |document| [document["_id"], @row_class.new(document)] }
  end

  # So an export matches the list it came from.
  def to_csv(columns, comparison = {})
    self.class.csv(self, columns, comparison)
  end

  class << self
    def csv(rows, columns, comparison = {})
      previous, keys, changing = comparison.values_at(:previous, :keys, :changing)
      CSV.generate do |csv|
        csv << columns.keys
        rows.each do |row|
          before = previous&.[](Array(keys).map { |key| row[key] })
          csv << columns.values.map do |field|
            value = row.value(field)
            CompareChange.cell(value, before&.value(field), compare: !previous.nil? && Array(changing).include?(field))
          end
        end
      end
    end
  end

  private

  def with(stages)
    self.class.new(@criteria, keys: @keys, sums: @sums, row_class: @row_class, derived: @derived, stages: @stages.merge(stages))
  end

  def grouping
    [
      {"$match" => @criteria.selector},
      {"$group" => {"_id" => @keys.to_h { |key| [key.to_s, "$#{key}"] }, **sum_stage}},
      # Flattened, so the keys sort and read like any other field.
      {"$addFields" => @keys.to_h { |key| [key.to_s, "$_id.#{key}"] }.merge(@derived)},
      {"$project" => {"_id" => 0}}
    ]
  end

  def sum_stage
    @sums.to_h { |name, expression| [name.to_s, {"$sum" => expression}] }
  end

  # A long period's groups can outgrow the memory a sort may use.
  def aggregate(stages)
    @criteria.collection.aggregate(stages, allow_disk_use: true)
  end
end
