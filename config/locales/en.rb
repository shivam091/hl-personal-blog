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
    },
    activemodel: {
      attributes: {
        request_log_clearance: {
          from: "Start date",
          to: "End date",
          local_only: "Only local request logs"
        },
        "google/sync_range": {
          from: "Start date",
          to: "End date"
        }
      }
    },
    mongoid: {
      attributes: {
        crawled_page: {
          url: "URL",
          last_modified_at: "Last modified",
          indexed: "Indexed"
        },
        feed_entry: {
          url: "URL",
          _id: "URL",
          name: "Title",
          description: "Description",
          type: "Type",
          published_at: "Published",
          last_modified_at: "Updated",
          tags: "Tags",
          categories: "Categories"
        },
        tag: {
          name: "Name"
        },
        category: {
          name: "Name"
        },
        page_view: {
          url: "URL",
          visitor_count: "Visitors",
          unique_visitor_count: "Unique visitors",
          updated_at: "Last updated"
        },
        page_like: {
          url: "URL",
          like_count: "Likes",
          updated_at: "Last liked",
          created_at: "First liked"
        },
        newsletter_subscriber: {
          email: "Email",
          country: "Country",
          subscribed_at: "Subscribed"
        },
        message: {
          name: "Name",
          email: "Email",
          message: "Message",
          recaptcha_score: "reCAPTCHA score",
          country: "Country",
          created_at: "Sent"
        }
      }
    },
    sessions: {
      new: {
        notice: "This application is for authorised users only. If you are not an authorised user, " \
          "end this session now by closing your browser. By accessing this system, you agree that " \
          "your activity may be monitored if unauthorised use is suspected."
      }
    }
  }
}
