# encoding: UTF-8

# A list counts all time until a span is picked, so every span, the default
# one included, is named in the URL to be told from all time. Lists judge
# nothing against an earlier span, so no comparison rides along.
class ListPeriod < Period
  def initialize(params, **options)
    super
    @all_time = params[:from].blank? && params[:to].blank?
  end

  def all_time?
    @all_time
  end

  def query
    all_time? ? {} : {from: from.iso8601, to: to.iso8601}
  end

  def preset_query(preset)
    from, to = preset_range(preset)
    {from: from.iso8601, to: to.iso8601}
  end

  def compare_query
    {}
  end
end
