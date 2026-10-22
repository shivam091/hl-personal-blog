# encoding: UTF-8

# Nil unless a comparison is picked, and only worth showing once the compared
# days have records, since logs are cleared over time and a change against
# nothing says nothing.
module PreviousPeriod
  def previous
    return @previous if defined?(@previous)

    earlier = self.class.new(period.previous) if period.compare?
    @previous = (earlier if earlier&.any?)
  end
end
