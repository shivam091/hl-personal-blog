# encoding: UTF-8

# One shape for every import and sync, so each one's outcome reads, and is
# judged, the same way.
SyncResult = Struct.new(:created, :updated, :unchanged, :errors) do
  class << self
    def empty
      new(0, 0, 0, [])
    end
  end

  def summary
    "#{created} created, #{updated} updated, #{unchanged} unchanged, #{errors.size} failed"
  end

  # Errors only fail a run that brought nothing in; otherwise it's partial.
  def failed?
    errors.any? && (created + updated + unchanged).zero?
  end
end
