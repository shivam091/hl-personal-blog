# Personal Blog

Rails 8 backend for the blog: serves the blog's content API and pulls in
external data for
an admin dashboard. Full-stack app (HAML views, Hotwire/Turbo + Stimulus,
Tailwind CSS).

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

## Dates and times

Shown as `12 Mar, 2026`, and times as `12 Mar, 2026 12:00 IST`
([config/locales/en.rb](config/locales/en.rb)). The app's time zone is IST
(`config.time_zone`), so anything picked or grouped by day counts IST
days; MongoDB still stores UTC. CSV exports keep ISO 8601 UTC timestamps so
they round-trip through imports and spreadsheets.

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
```

On Render, set the `RAILS_MASTER_KEY` environment variable to the contents of
`config/credentials/production.key`; no other secret env vars are needed.
Tests don't need a key: they use a local mongod and stub the admin login.

| Concern | Where it's configured |
|---|---|
| MongoDB Atlas | [config/mongoid.yml](config/mongoid.yml) |
| CORS (blog frontend origins) | [config/initializers/cors.rb](config/initializers/cors.rb) |

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
