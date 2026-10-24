# Personal Blog

Rails 8 backend for the blog: serves the blog's content API and pulls in
external data from Google's APIs and Mixpanel for an admin dashboard. Full-stack app
(HAML views, Hotwire/Turbo + Stimulus, Tailwind CSS).

## Stack

- Ruby 4.0.6, Rails 8.1.3
- **Mongoid / MongoDB Atlas** — the only datastore: the blog's one live
  database (`MONGODB_URI` + `MONGODB_DB`), shared with the blog frontend.
  See [config/mongoid.yml](config/mongoid.yml). No Active Record, so no
  Active Storage, Action Cable, or Solid Queue/Cache/Cable.
- **Active Job** with the in-process `:async` adapter
- **HAML** instead of ERB (`haml-rails`)
- **Turbo + Stimulus** (Hotwire), importmap, Propshaft — no JS bundler
- **Tailwind CSS v4** via `tailwindcss-rails` (standalone CLI, no Node).
  Styles are utility classes in the views; the entry point is
  [app/assets/tailwind/application.css](app/assets/tailwind/application.css).
  `bin/dev` runs `tailwindcss:watch`, and `assets:precompile` builds it.
- **RSpec** for tests, against a local `mongod`, with DatabaseCleaner
  clearing Mongoid collections between examples

## One-time local setup

Tests need a local MongoDB. Install it with:

```bash
bash script/install_local_services.sh
```

That script needs `sudo` and will prompt for your password. It:
- installs MongoDB 8.0 from the official repo and starts `mongod`

Then:

```bash
bundle install
bin/dev                      # starts the Puma server (needs config/master.key)
```

Get `config/master.key` from the project owner; it's git-ignored and
decrypts the development credentials (see [Configuration](#configuration)).

Background jobs use Active Job's `:async` in-process adapter in every
environment, so there's no separate worker.

Mongo collections are schemaless and created lazily on first write, so
there are no migrations. `bin/rails db:mongoid:create_indexes` creates the
indexes models declare; the Docker entrypoint runs it on every deploy.

## Login

Every page except `/up` requires signing in at `/session/new` with the
`admin.username` and `admin.password` from the Rails credentials (nobody can
sign in while either is blank). Sessions last 12 hours, changing either one signs
everyone out, and login attempts are limited to 10 per 3 minutes. See
[app/controllers/concerns/authentication.rb](app/controllers/concerns/authentication.rb).

## Crawled pages

`/crawled-pages` tracks the blog's pages and whether Google has indexed
them (`CrawledPage`, a backend-only collection keyed on URL). Pages come
from the sitemap and can't be added or edited here; besides marking their
indexed status, the list exports CSVs in the crawled-pages layout:

```csv
#,URL,Last modified,Status
1,https://harshal-ladhe.vercel.app,2026-07-05T12:07:01.000Z,Yes
```

`Status` "Yes" means indexed; blank means not. The same export works from
the command line:

```bash
bin/rails 'crawled_pages:export[path/to/out.csv]'   # or no path for stdout
```

### Sitemap sync

[`SitemapSyncService`](app/services/sitemap_sync_service.rb) reads the blog's
sitemap (`/sitemap.xml` at credentials `blog.url`, following a sitemap
index if there is one), creates a crawled page for each new URL, and updates last modified on
known ones. It never changes indexed status (only Google's crawl report
knows that) and never deletes pages that dropped out of the sitemap.

- **At 00:00 UTC daily:** the [daily workflows](#daily-workflows) run
  `bin/rails crawled_pages:sync_sitemap`. The task runs the sync in its own
  process, not through Active Job, because the process exits when it's done.
- **On demand:** **Sync sitemap** on the crawled pages list queues
  [`SyncSitemapJob`](app/jobs/sync_sitemap_job.rb) in the web process.

A run with no pages synced and errors exits non-zero, so it shows as failed;
the logs list each skipped URL.

## Feed entries

`/feed-entries` lists everything the blog's Atom feed publishes
(`FeedEntry`, keyed on the entry's URL), with its type, tags, and
categories. Tags (`Tag`) and categories (`Category`) are collections of
their own; entries refer to them by id. The list can be filtered by type,
title, URL, tag, category, and published/updated dates, sorted, paged, and
exported. Entries can't be added, edited, or deleted here: the feed owns
them.

Each feed `<entry>` maps to:

| Feed | Field |
|---|---|
| `<id>` | `_id` (the URL, also `url`) |
| `<title>` | `name` |
| `<content>` (or `<summary>`) | `description` |
| `<category scheme="urn:taxonomy:type">` | `type`: `post`, `tutorial`, or `snippet` |
| `<category scheme="urn:taxonomy:tag">` | `tags` |
| `<category scheme="urn:taxonomy:category">` | `categories` |
| `<published>` | `published_at` |
| `<updated>` | `last_modified_at` |

Exports put tags and categories comma-separated in one cell:

```csv
#,URL,Title,Description,Type,Published,Updated,Tags,Categories
1,https://harshal-ladhe.vercel.app/post/css/css-z-index-and-stacking-contexts,Mastering CSS z-index,Learn how…,post,2026-10-08T05:10:25.000Z,2026-10-08T05:10:25.000Z,"css, z-index",CSS
```

Syncing matches on URL: new URLs are added, changed entries
updated, and any tag or category not seen before is created. Entries that
drop out of the feed are kept.

```bash
bin/rails 'feed_entries:export[path/to/out.csv]'   # or no path for stdout
bin/rails feed_entries:sync_feed
```

### Feed sync

[`FeedSyncService`](app/services/feed_sync_service.rb) reads the feed at
`/atom.xml` on credentials `blog.url` (`https://harshal-ladhe.vercel.app`
in both development and production). An `ATOM_FEED_URL` environment
variable overrides it, to point at another feed without re-encrypting
credentials. **Sync feed** on the list queues
[`SyncFeedJob`](app/jobs/sync_feed_job.rb).

At 00:00 UTC daily, the [daily workflows](#daily-workflows) run
`bin/rails feed_entries:sync_feed`, in its own process rather than through
Active Job, because the process exits when it's done. A run with no entries
synced and errors exits non-zero, so it shows as failed; the logs list each
skipped entry.

Each sync then marks its new entries on Google Analytics' charts as
annotations ([`AnnotationService`](app/services/google/analytics/annotation_service.rb)).
For that, the service account must be an Editor of the property (Admin →
Property access management).

## Mixpanel

`/mixpanel` reports what the blog sends to Mixpanel alongside Google
Analytics: how long readers were active on each page and how far they
scrolled, rage clicks, dead clicks and script errors, a day's funnel from
viewing a page to subscribing, and the share of readers whose browser
blocked Google Analytics. Session replays and heatmaps stay in Mixpanel.

[`Mixpanel::SyncService`](app/services/mixpanel/sync_service.rb) copies each
day from Mixpanel's raw export, one query per day against the project's 60
an hour, into daily page, site and issue stats. Only events from the blog's
own host (`blog.url`) count, so a local run or a preview deploy sending to
the same project is left out. Recent days are fetched again, since Mixpanel
accepts events sent days late.

| Rake task | Page button | Does |
|---|---|---|
| `mixpanel:sync[days]` | **Sync** | Copies the last N days (default 3) |
| `mixpanel:annotate` | **Mark posts** | Marks posts published in the last 30 days on Mixpanel's charts |
| `mixpanel:describe` | **Describe events** | Sends the blog's event and property descriptions ([`TrackingPlan`](app/models/mixpanel/tracking_plan.rb)) to Mixpanel's Lexicon |

The retention card needs Mixpanel's Query API, which its Free plan doesn't
include; the sync skips it there rather than failing.

## Request logs

Every request (except `/up` and assets) is saved as a
[`RequestLog`](app/models/request_log.rb) by the
[`RequestLogger`](app/middlewares/request_logger.rb) middleware, after the
response has been sent. It looks up the client's IP through
[`IpInfoService`](app/services/ip_info_service.rb) (cached per IP for a day;
local and private IPs are skipped). Each log is
keyed by its request id (`X-Request-Id`, also tagged on production log
lines).

`/request-logs` lists them, searchable by URL, time, IP, method, and user
agent, with tabs by status class, sortable, paginated, and exportable as CSV.
Each log's page shows the timing, the client's location and network, the
params, the headers (cookies and credentials are never stored), and any
exception.

Logs are never deleted automatically. They share the blog's live database
and its storage quota, so clear old ones from **Clear logs…** on the list:
pick a start and end date (whole days, IST) and
[`ClearRequestLogsJob`](app/jobs/clear_request_logs_job.rb) deletes them in
the background through Active Job's `:async` adapter, inside the web process
(see [Background jobs](#background-jobs)).

## Background jobs

Jobs run on Active Job's `:async` adapter: a thread pool inside the Puma web
process, in every environment. There's no Redis, queue database, or separate
worker service to run or pay for on Render. The trade-off is that a job
queued in memory is lost if the process stops before it starts, e.g. on a
deploy or restart. That's acceptable for the jobs here: clearing logs is a
single `deleteMany` that MongoDB finishes even if the app goes away, and an
unstarted one can simply be requested again. If jobs ever need to survive
restarts, move to a persistent adapter and a Render background worker.
Scheduled work doesn't go through the web process at all; see below.

## Scheduled sync

Render's free web service sleeps when idle and its Cron Jobs aren't free,
so the syncs run as a scheduled GitHub Actions workflow,
[.github/workflows/scheduled-sync.yml](.github/workflows/scheduled-sync.yml),
at 00:00, 08:00 and 16:00 UTC (05:30, 13:30 and 21:30 IST). It runs
[`bin/scheduled-sync`](bin/scheduled-sync) against the production database,
which runs these rake tasks, each even if one before it failed:

| Task | Covers |
|---|---|
| `google:search_console:sync` | Search Console stats, from the first day not yet final |
| `google:analytics:sync[7]` | Google Analytics stats, last 7 days |
| `google:recaptcha:sync` | reCAPTCHA scores, every day Google still holds |
| `google:safe_browsing:sync` | Every outbound link readers have clicked, against Google Safe Browsing (credentials `google.api_key`) |
| `mixpanel:sync` | Mixpanel stats, last 3 days (credentials `mixpanel.*`) |
| `mixpanel:annotate` | Marks posts published in the last 30 days on Mixpanel's charts |

`google:crux:sync` (Web Vitals history) isn't scheduled: the blog has too
few Chrome users for the Chrome UX Report to cover, so it would fail every
run. Run it by hand, or from the Web Vitals history page, to check whether
it has started reporting.

The same script runs by hand, against development unless told otherwise:

```bash
bin/scheduled-sync                        # development database
RAILS_ENV=production bin/scheduled-sync   # live database
DAYS=90 bin/scheduled-sync                # a longer window for the Analytics stats
```

Every run is listed under **Sync requests**, started by "rake". GitHub
can start a scheduled run some minutes late, most of all on the hour.

One-time setup:

1. Add an Actions secret `RAILS_MASTER_KEY` with the contents of
   `config/credentials/production.key` (repo → Settings → Secrets and
   variables → Actions).
2. Let GitHub's runners reach MongoDB: their addresses change, so Atlas →
   Network Access must allow `0.0.0.0/0`.
3. Try it from the Actions tab: **Scheduled sync** → **Run workflow**.

GitHub only schedules workflows from the default branch, and in a public
repository pauses them after 60 days without a commit.

### Daily workflows

More workflows run once a day, each on its own so one failing doesn't mark
another failed. They need the same one-time setup as the scheduled sync,
and each can be started by hand from the Actions tab.

| Workflow | When (UTC) | Task | Covers |
|---|---|---|---|
| [Scheduled blog sync](.github/workflows/scheduled-blog-sync.yml) | 00:00 | `crawled_pages:sync_sitemap` | The blog's sitemap |
| [Scheduled blog sync](.github/workflows/scheduled-blog-sync.yml) | 00:00 | `feed_entries:sync_feed` | The blog's Atom feed |
| [Scheduled blog sync](.github/workflows/scheduled-blog-sync.yml) | 00:00 | `google:search_console:submit_sitemap` | Submitting the sitemap to Search Console (the service account must be an Owner or Full user) |
| [Scheduled blog sync](.github/workflows/scheduled-blog-sync.yml) | 00:00 | `google:search_console:inspect_new_entries` | URL Inspection of entries from the last 30 days not yet indexed |
| [Scheduled URL inspection](.github/workflows/scheduled-url-inspection.yml) | 00:00 | `google:search_console:inspect_urls[2000]` | URL Inspection of every crawled page |
| [Scheduled PageSpeed](.github/workflows/scheduled-page-speed.yml) | 02:00 | `google:page_speed:sync` | PageSpeed Insights on the 30 least recently tested pages (credentials `google.api_key`) |

A workflow listed with several tasks runs them in the order shown, each
even if one before it failed.

The URL inspection's limit is Google's daily quota per property, so every
page is inspected while the blog has fewer pages than that. It runs at the
same time as the sitemap sync, so a page the sitemap adds is first inspected
the next day.

### Sync digest

[Scheduled sync digest](.github/workflows/scheduled-sync-digest.yml) runs
`sync_requests:digest` at 03:30 UTC (09:00 IST) and mails one summary of the
last 24 hours of syncs: how many ran and how each ended, every failed,
partial or stalled one with its first errors, and when each kind last
synced. A day with no syncs at all is flagged too, since it means the
schedule itself stopped.

It goes to `mailer.notify_to` in the production credentials, sent through
Brevo like the newsletter:

```yaml
mailer:
  from: Name <verified-sender@example.com>
  notify_to: you@example.com
```

Without that address the task fails, so the workflow run shows as failed
rather than quietly sending nothing. Run it by hand with
`RAILS_ENV=production bin/rails sync_requests:digest`.

## Dates and times

Shown as `12 Mar, 2026`, and times as `12 Mar, 2026 12:00 IST`
([config/locales/en.rb](config/locales/en.rb)). The app's time zone is IST
(`config.time_zone`), so anything picked or grouped by day counts IST
days; MongoDB still stores UTC. CSV exports keep ISO 8601 UTC timestamps so
spreadsheets read them unambiguously.

## Navigation

The top nav is defined in [config/navigation.yml](config/navigation.yml):
plain links, or dropdowns grouped by where the data comes from. Adding a
page means adding its named route there.

## List pages

Index pages build their lists from independent, server-side pieces in
[lib/](lib/), each with a view helper:

| Piece | Reads params | View helper |
|---|---|---|
| [`Filtering`](lib/filtering.rb) — search fields ([`Contains`](lib/filtering/contains.rb), [`DateRange`](lib/filtering/date_range.rb), [`Select`](lib/filtering/select.rb)) and [`Tabs`](lib/filtering/tabs.rb) | per field, e.g. `q`, `modified_from` | `search_panel`, `filter_tabs` |
| [`Sorting`](lib/sorting.rb) — whitelisted columns | `sort`, `direction` | `sort_header` |
| [`Pagination`](lib/pagination.rb) — page and page size | `page`, `per` | `pagination_nav` |

```ruby
# controller
@filtering = Filtering.new(params, fields: [ Filtering::Contains.new(:q, field: :title, label: "Title contains") ])
@sorting = Sorting.new(params, columns: { "title" => "asc", "created_at" => "desc" })
@pagination = Pagination.new(@sorting.apply(@filtering.apply(Post.all)), params, per_page_options: [ 25, 50 ])
```

```haml
-# view: `keep:` lists the other pieces whose params each control's links preserve
= search_panel @filtering, keep: [ @sorting, @pagination ]
= sort_header @sorting, "Title", "title", keep: [ @filtering, @pagination ]
= pagination_nav @pagination, keep: [ @filtering, @sorting ]
```

Every list page also answers `.csv` with all matching rows (not just the
current page), linked as **Export CSV** via
`list_url(@filtering, @sorting, format: :csv)` and built by the model's
`to_csv`.

See [app/controllers/crawled_pages_controller.rb](app/controllers/crawled_pages_controller.rb)
for a full example.

## Configuration

Secrets live in encrypted Rails credentials, one file per environment:

| Environment | Encrypted file (committed) | Key (git-ignored) |
|---|---|---|
| development (and test) | `config/credentials.yml.enc` | `config/master.key` |
| production | `config/credentials/production.yml.enc` | `config/credentials/production.key` |

Edit them with `bin/rails credentials:edit` (development) or
`bin/rails credentials:edit --environment production`. Both use this layout:

```yaml
secret_key_base: ...

mongodb:
  uri: mongodb+srv://user:password@cluster.mongodb.net/?appName=my-app
  database: personal-blog
  # auth_source: admin       # optional, defaults shown
  # max_pool_size: 10

admin:
  username: ...
  password: ...

cors:
  origins:
    - http://localhost:3000

# Request log IP lookups. Each endpoint's JSON is merged in order; %{ip} is
# replaced with the client IP. Swap in richer endpoints on a paid plan.
ipinfo:
  token: ...
  endpoints:
    - https://ipinfo.io/%{ip}/json
    - https://api.ipinfo.io/lite/%{ip}

# The blog's address. Its sitemap, Atom feed and logo, and the links to it
# in mail and on pages here, are all taken from it. ATOM_FEED_URL still
# overrides the feed.
blog:
  url: https://harshal-ladhe.vercel.app

# A Mixpanel service account (Organization settings → Service accounts) with
# at least the Analyst role on the blog's project. project_id is the number
# in the project's URL; data_host is the export host of the project's region:
# data.mixpanel.com (US), data-eu.mixpanel.com or data-in.mixpanel.com.
mixpanel:
  project_id: "1234567"
  service_account_username: ...
  service_account_secret: ...
  data_host: data.mixpanel.com
```

On Render, set the `RAILS_MASTER_KEY` environment variable to the contents of
`config/credentials/production.key`; no other secret env vars are needed.
Tests don't need a key: they use a local mongod and stub the admin login
and the blog's address.

| Concern | Where it's configured |
|---|---|
| MongoDB Atlas | [config/mongoid.yml](config/mongoid.yml) |
| CORS (blog frontend origins) | [config/initializers/cors.rb](config/initializers/cors.rb) |

Each service class has setup instructions (what credential to generate,
where to grant access) in its file header.

## Tests

```bash
bundle exec rspec
```

## Conventions

- Every `.rb` file starts with `# encoding: UTF-8`.
- Collections come in two kinds, both in the one live database:
  - **Frontend-shared** (ones the blog frontend also reads or writes, e.g.
    `page_views`): the frontend owns their schema, so models alias its
    camelCase field names and declare **no indexes** (each model's spec
    checks this). A model the backend never writes to is read-only
    (`include ReadOnly`).
  - **Backend-owned** (anything new that only the backend reads and writes):
    ordinary Mongoid models with snake_case fields, `Mongoid::Timestamps`,
    and whatever `index`es they need.
- Models are Mongoid documents (`include Mongoid::Document`). Active Record
  isn't loaded at all — there's no `ApplicationRecord`, `database.yml`, or
  migrations.
- Icons come from one sprite, [app/assets/images/icons.svg](app/assets/images/icons.svg),
  drawn with `icon("name")` ([IconHelper](app/helpers/icon_helper.rb)); no
  inline SVGs. To add one, add a `<symbol id="name" viewBox="0 0 24 24">`
  with just its paths (the helper sets the stroke). Buttons and links
  elsewhere pair an icon with text; inside tables, controls and yes/no
  indicators are icon-only and get `label:` (or an `aria-label` on the
  link) so screen readers still name them. `spec/requests/icons_spec.rb`
  fails if a page uses an icon the sprite lacks.
