# encoding: UTF-8

# Ruby rather than YAML so long strings can be split across lines and
# commented, which YAML makes awkward.
{
  en: {
    # One format across the app, so dates read the same on every page; times
    # carry their zone so nobody has to guess whether they're IST or UTC.
    date: {
      formats: {
        default: "%-d %b, %Y",
        short: "%-d %b, %Y",
        long: "%-d %b, %Y"
      }
    },
    time: {
      formats: {
        default: "%-d %b, %Y %H:%M %Z",
        short: "%-d %b, %Y %H:%M %Z",
        long: "%-d %b, %Y %H:%M %Z"
      }
    }
  }
}
