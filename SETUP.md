# Setup and local development

## Docker (recommended — no local PostgreSQL)

Postgres and Redis run in containers; your filesystem is bind‑mounted into the `web` service so you can edit code on the host.

**Requirements:** Docker Desktop (or Docker Engine + Compose v2)

```bash
docker compose up --build
```

When the `web` service is up:

- API: `http://localhost:3000`
- Postgres is available on host port `5432` (optional; for GUI clients if you want to inspect data)
- Redis on host port `6379` (optional)

Environment inside `web`:

- `DATABASE_URL` → PostgreSQL service `db`
- `REDIS_URL` → Redis service `redis`

`docker compose` runs `bin/rails db:prepare` before `rails server`, so the database is created/migrated on boot.

### After changing the Gemfile

Rebuild the web image so bundled gems match:

```bash
docker compose build web
docker compose up
```

Or one-off install inside a throwaway container:

```bash
docker compose run --rm web bundle install
```

### Running tests in Docker

Start Postgres and Redis (the `run` command does not always start sibling services on all Compose versions):

```bash
docker compose up -d db redis
docker compose run --rm \
  -e RAILS_ENV=test \
  -e DATABASE_URL=postgresql://postgres:postgres@db:5432/bitly_clone_assignment_test \
  -e REDIS_URL=redis://redis:6379/0 \
  web sh -c "bundle exec rails db:test:prepare && bundle exec rspec"
```

If Postgres and Redis are already up on the host (`docker compose up -d db redis`) and you run Ruby on the host, export URLs first (Compose exposes ports `5432` and `6379`):

```bash
export DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/bitly_clone_assignment_test
export REDIS_URL=redis://127.0.0.1:6379/0
bundle exec rails db:test:prepare
bundle exec rspec
```

### Stopping and removing volumes

```bash
docker compose down          # keep Postgres data
docker compose down -v         # also delete the named volume (fresh DB)
```

---

## Non-Docker (optional)

If you prefer host Ruby and only use Docker for databases:

```bash
docker compose up db redis -d
export DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/bitly_clone_assignment_development
export REDIS_URL=redis://127.0.0.1:6379/0
bin/rails db:prepare
bin/rails server
```

You still do **not** need a standalone Postgres install as long as the `db` container is running.

---

## Production (Fly.io)

See the main [README](README.md) for high-level notes. This section is the **step-by-step deploy** guide.

### Prerequisites

- [Fly CLI](https://fly.io/docs/flyctl/install/) (`fly version`)
- Logged in: `fly auth login`
- This repo’s production image: root **`Dockerfile`**. `bin/docker-entrypoint` runs **`rails db:prepare`** when the container starts **`rails server`**, so the schema is applied on boot.

### 1. App name and `fly.toml`

- Open **`fly.toml`** and set **`app`** to a unique Fly app name (or run `fly apps create <name>` and match that name).
- Set **`primary_region`** to the region closest to you (same region as Postgres and Redis is best).

### 2. Create the Fly app (if it does not exist yet)

```bash
fly apps create <your-app-name>
```

Or run **`fly launch`** once from the repo root and align the generated `fly.toml` with this project’s `Dockerfile` and **`internal_port` (8080)** as in the committed `fly.toml`. Production uses **Thruster**: **`HTTP_PORT`** must match `internal_port`; **`TARGET_PORT`** is where Puma listens (see `[env]` in `fly.toml`).

### 3. Postgres (Fly Postgres)

Create a Postgres cluster (pick region to match the app):

```bash
fly postgres create --name <your-pg-cluster-name> --region <region>
```

Attach it to the Rails app (Fly wires **`DATABASE_URL`** on the app):

```bash
fly postgres attach <your-pg-cluster-name> -a <your-app-name>
```

Confirm: `fly secrets list -a <your-app-name>` should show `DATABASE_URL` (or equivalent).

### 4. Redis (Upstash on Fly)

Create Redis with eviction (see [Fly.io Redis LRU and eviction](#flyio-redis-lru-and-eviction) below). Example:

```bash
fly redis create --name <your-redis-name> --region <region> --enable-eviction
```

Get the private URL:

```bash
fly redis status <your-redis-name>
```

Set it on the app:

```bash
fly secrets set REDIS_URL="<paste Private URL from status output>" -a <your-app-name>
```

### 5. Rails master key

Production needs **`RAILS_MASTER_KEY`** to decrypt `config/credentials.yml.enc`. From your machine (never commit `config/master.key`):

```bash
fly secrets set RAILS_MASTER_KEY="$(cat config/master.key)" -a <your-app-name>
```

### 6. Public URL for short links (recommended)

So `/encode` returns stable `https://…` links instead of an internal hostname:

```bash
fly secrets set PUBLIC_APP_ROOT="https://<your-app-name>.fly.dev" -a <your-app-name>
```

Use your real Fly hostname (or a custom domain if you add one).

### 7. Deploy

```bash
fly deploy -a <your-app-name>
```

Open the app:

```bash
fly apps open -a <your-app-name>
```

Health check: `https://<your-app-name>.fly.dev/up`

### 8. Smoke test (encode / decode)

```bash
curl -s -X POST "https://<your-app-name>.fly.dev/encode" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/fly-test"}'
```

Then decode with the returned `shortened_link` in the JSON body (same as local).

### Useful commands

- Logs: `fly logs -a <your-app-name>`
- SSH: `fly ssh console -a <your-app-name>`
- Rails console: `fly console -a <your-app-name>` (if enabled for your setup)
- Scale VM: `fly scale show` / `fly scale memory` (see Fly docs)

### Fly.io Redis LRU and eviction

Fly’s managed Redis is **Upstash Redis** (`fly redis create`). You cannot set Redis’s native `maxmemory-policy allkeys-lru` on that product the same way as self-hosted Redis. Instead:

1. **Create** a database (same region as the app when possible):

   ```bash
   fly redis create --name <your-redis-name> --region <region> --enable-eviction
   ```

   Use **`--enable-eviction`** so writes keep working when the plan’s size limit is reached; keys can be dropped instead of failing the app. Without it, Redis may reject writes at the limit (`--disable-eviction` is the opposite).

2. **Attach** the connection string to your app (Fly sets a secret such as `REDIS_URL`; confirm name in the output of `fly redis create` / dashboard):

   ```bash
   fly secrets set REDIS_URL="<paste connection URL from fly redis status or dashboard>"
   ```

3. **Why this still fits “LRU” in practice**

   - **App:** every successful decode from Redis refreshes **`EXPIRE`** on that key (see `DecodeCache`), so frequently hit slugs stay “fresh” and are less likely to age out on TTL alone.
   - **Server:** with **eviction enabled**, Upstash removes data when space is tight; its eviction favors keys with TTL (your decode keys use **`EXPIRE`**). That is not identical to open-source **`allkeys-lru`**, but it targets the same goal: keep the active set and shed cold entries. For strict open-source LRU semantics, run **your own** Redis VM with `maxmemory` + `allkeys-lru` and point `REDIS_URL` at it.

4. **Optional:** set `PUBLIC_APP_ROOT` on the app to your public HTTPS origin so `/encode` returns stable short links (see app `ShortLinksController`).

### Local Redis and open-source LRU

The **`redis`** service in `docker-compose.yml` runs:

`redis-server --maxmemory 128mb --maxmemory-policy allkeys-lru`

So local development uses **approximate LRU** eviction when the 128 MB cap is hit, matching how you would tune a self-managed Redis in production.
