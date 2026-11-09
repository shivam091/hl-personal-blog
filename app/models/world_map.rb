# encoding: UTF-8

# Drawn on the server, so the map needs no third-party map script or tile
# service. Natural Earth's shapes because they're public domain, projected
# in Equal Earth because it keeps each country's area true, so a big
# country doesn't look busier than it is. 1:50m rather than 1:110m, so
# small countries such as Singapore and Malta are drawn too, and those
# still too small to point at carry a dot.
class WorldMap
  Country = Struct.new(:code, :name, :path, :dot)

  class << self
    def width
      data.fetch("width")
    end

    def height
      data.fetch("height")
    end

    def countries
      @countries ||= data.fetch("countries").map { |code, shape| Country.new(code, shape.fetch("name"), shape.fetch("d"), shape["dot"]) }
    end

    def codes
      @codes ||= countries.map(&:code).to_set
    end

    private

    # Read once per process; the file never changes while the app runs.
    def data
      @data ||= JSON.parse(Rails.root.join("config/world_map.json").read)
    end
  end
end
