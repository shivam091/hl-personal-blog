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

## Dates and times

Shown as `12 Mar, 2026`, and times as `12 Mar, 2026 12:00 IST`
([config/locales/en.rb](config/locales/en.rb)). The app's time zone is IST
(`config.time_zone`), so anything picked or grouped by day counts IST
days; MongoDB still stores UTC.

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

cors:
  origins:
    - http://localhost:3000
```

On Render, set the `RAILS_MASTER_KEY` environment variable to the contents of
`config/credentials/production.key`; no other secret env vars are needed.
Tests don't need a key: they use a local mongod.

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