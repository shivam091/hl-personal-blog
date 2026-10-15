# encoding: UTF-8

# The blog's own addresses, all built from credentials blog.url, so moving
# the blog to a new domain is one change rather than one per feature.
class Blog
  class << self
    # Without a trailing slash, so paths can be appended as they are.
    def url
      Rails.application.credentials.blog&.[](:url).to_s.chomp("/").presence
    end

    def sitemap_url
      "#{url}/sitemap.xml" if url
    end

    def atom_feed_url
      "#{url}/atom.xml" if url
    end

    # From the blog itself, which is always up, unlike this app on Render's
    # free plan, where a sleeping app would leave a broken image. A PNG, as
    # Gmail won't show SVG.
    def logo_url
      "#{url}/assets/img/icons/favicon.png" if url
    end
  end
end
