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

See the main [README](README.md) for deploy notes.

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
