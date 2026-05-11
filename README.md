# URL Shortener

ShortLink-style **JSON API** (Ruby / Rails): **`POST /encode`** and **`POST /decode`** both accept **`Content-Type: application/json`** with a **`url`** field (long URL to shorten, or short URL / slug to resolve). Responses use **`shortened_link`** / **`original_link`**. Implemented in **Ruby** (Rails API mode).

---

## Submission and demo deployment

- Push to **GitHub** (public repo is fine per brief), then submit on the assignment portal.
- Run locally: [SETUP.md](SETUP.md) (Docker Compose at the top).
- Deploy to any **free-tier host** you prefer; this repo includes **`fly.toml`** (Puma listens on **`PORT`**, default **8080** on Fly) and a full **Fly.io** walkthrough in [SETUP.md — Production (Fly.io)](SETUP.md#production-flyio). Set secrets such as **`DATABASE_URL`** (from Fly Postgres attach), **`REDIS_URL`**, **`RAILS_MASTER_KEY`**, and optionally **`PUBLIC_APP_ROOT`** for stable short links.
- **Live demo (Fly.io):** [https://bitly-clone-assignment.fly.dev/](https://bitly-clone-assignment.fly.dev/) — health check: [https://bitly-clone-assignment.fly.dev/up](https://bitly-clone-assignment.fly.dev/up).

### Quick curls

```bash
curl -X POST http://localhost:3000/encode \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/long/path"}'
```

```bash
curl -X POST http://localhost:3000/decode \
  -H 'Content-Type: application/json' \
  -d '{"url":"http://localhost:3000/<slug>"}'
```

Replace host and `<slug>` with values from the encode response (same JSON pattern as `/encode`). For the public Fly deployment, use `https://bitly-clone-assignment.fly.dev` as the host instead of `localhost:3000`.

---

## Assignment brief — coverage

| Requirement | How this repo satisfies it |
|-------------|----------------------------|
| Language **Ruby** | Rails 8 API app; see [`.ruby-version`](.ruby-version). |
| **`POST /encode`** and **`POST /decode`**, **JSON** | [`config/routes.rb`](config/routes.rb), [`ShortLinksController`](app/controllers/short_links_controller.rb) — JSON body `{ "url": "..." }` on both endpoints; responses use `shortened_link` / `original_link` (or `error`). |
| Encode ↔ decode round-trip | Same long URL after encode + decode; covered in [request specs](spec/requests/short_links_spec.rb). |
| **Decode after restart** | Mappings live in **PostgreSQL** (`links` table). **Redis** is an optional cache only; restart or empty Redis still decodes from the DB. |
| **Run instructions** (separate file) | **[SETUP.md](SETUP.md)** — Docker, env vars, tests, Fly.io Redis. |
| **Tests for both endpoints** | [Request specs](spec/requests/short_links_spec.rb) for `/encode` and `/decode`; plus [service specs](spec/services/). |
| **Attack vectors** in README | [Security](#security-risks--mitigations) below. |
| **Scale + collision approach** in README | [Algorithm](#algorithm-and-uniqueness), [Scaling](#scaling), and [Collision handling](#collision-handling) below. |

---

## Persistence after restart

**PostgreSQL** is the source of truth: each shortened URL maps to a row with `original_url` and a unique **`slug`**. Redis only speeds up decode; if the app or Redis restarts, **`POST /decode`** still resolves via Postgres (cache repopulates on demand).

---

## Tech stack

- **Ruby 3.2.x** (see [`.ruby-version`](.ruby-version)), **Rails 8.1.x** (API mode)
- **PostgreSQL**: canonical store for `{ slug ↔ original_url }`, unique constraints on `original_url` and `slug`
- **Redis**: decode cache (slug → original URL), write-through after encode; **LRU-aligned** behavior (see below)
- **Docker Compose** for local development (app + Postgres + Redis)
- Tests: **RSpec** (`bundle exec rspec` — set `DATABASE_URL` / `REDIS_URL` as in [SETUP.md](SETUP.md), or run via Docker Compose)

---

## Local development (Docker)

We do not need PostgreSQL or Redis installed on the host.

```bash
docker compose up --build
```

API: `http://localhost:3000`. Full runbook: [SETUP.md](SETUP.md) (tests, hybrid host-Ruby + container DB, Fly.io Redis).

---

## API contract

Prefer routes **exactly** as stated in the brief (confirm with interviewer if ambiguous):

| Method | Path | Request | Success response |
|--------|------|---------|-------------------|
| `POST` | `/encode` | JSON body: `{ "url": "<original>" }` | `{ "shortened_link": "<base>/<slug>" }` |
| `POST` | `/decode` | JSON body: `{ "url": "<short-url-or-slug>" }` | `{ "original_link": "<url>" }` |

**HTTP status codes** (see request specs): invalid URL → **422**; missing `url` → **422**; unknown slug on decode → **404**.

**Why `POST` for both:** keeps a uniform **JSON-over-HTTP** API (same `Content-Type`, same `url` field shape), avoids long URLs in query strings and query-length limits, and matches how many clients call internal APIs.

Set **`PUBLIC_APP_ROOT`** in production if we need a stable public base URL for `shortened_link` (otherwise the request host is used).

---

## Algorithm and uniqueness

**Slug from the database:** insert row → numeric `id` → Base62 → stored as **`slug`** (with a unique index). Responses read **`slug`** directly; Postgres remains authoritative.

- **Uniqueness:** enforced by Postgres (`UNIQUE` on `slug`, `UNIQUE` on `original_url`). Horizontally scaled Rails processes rely on the database for a single global namespace.
- **Collision problem (brief):** shortened codes are **not** truncated hashes of the URL (which can collide). Each insert gets a new monotonic **`id`**; **Base62(`id`)** is stored as **`slug`** with a **`UNIQUE`** index. Two different rows cannot receive the same `id`, so two different active slugs cannot collide. At most one process “wins” on insert; concurrent encodes of the **same** long URL dedupe on **`original_url`** uniqueness.
- **Trade-off:** slugs correlate with insertion order; production mitigations include rate limits, abuse monitoring, longer random tokens — out of minimal assignment scope unless we extend.

---

## Caching (`/decode`) — Postgres + Redis

1. **Redis read:** slug → cached `original_url` (key prefix `shortlink:v1:`).
2. **Miss:** load from Postgres, then **populate Redis**.
3. **`/encode`** success: **write-through** to Redis so the next decode is fast.

Treat Redis as **non-authoritative**: eviction or Redis downtime only affects latency and DB load; correctness comes from Postgres.

### Redis LRU (hot working set)

Two layers keep **recently used** decode entries favored under skewed traffic (e.g. Pareto-style “hot” slugs):

1. **Application — recency on hit:** on each cache **hit**, the app runs **`EXPIRE`** on the key so frequently resolved slugs keep a full **TTL** window (`DecodeCache`).
2. **Redis server — eviction under memory cap:** for Redis, set **`maxmemory`** and **`maxmemory-policy allkeys-lru`**. **Docker Compose** runs local Redis with **`allkeys-lru`** and a **`maxmemory`** cap so cold keys drop first when full.

**Fly.io managed Redis (Upstash)** does not expose classic `allkeys-lru` the same way; enable **eviction** on the database so writes do not fail at the size limit. See [SETUP.md — Fly.io Redis LRU and eviction](SETUP.md#flyio-redis-lru-and-eviction).

---

## Scaling

This demo doesn’t require implementing full large-scale infrastructure, but it should show an understanding of the bottleneck and what to do next.

<img width="781" height="381" alt="diagram" src="https://github.com/user-attachments/assets/b38dada8-2edb-40b5-a936-c0a8469dd7ef" />


- **Target scale:** around **10k–100k requests/sec**.
- Assume **read-heavy traffic**, so we optimize the `/decode` path.
- **API gateway + split services (conceptual):** the gateway routes decode requests to **read services** and encode requests to **write services**. That way, autoscaling can focus on the read side without over-provisioning writes.
- **Load balancing + autoscaling (read services):** multiple read service instances behind a load balancer; auto-scale based on latency/CPU.
- **Read path:** read service checks **Redis** first (decode cache). On cache miss it falls back to **PostgreSQL**.
- **Redis HA:** run Redis in a high-availability setup (replication + automatic failover) and still keep eviction bounded with an LRU-style policy so the hot working set remains cached.
- **PostgreSQL safety:** take regular snapshots/backups and keep **at least one replica** that can be promoted if the primary has an emergency failure.
- **Source of truth:** Postgres remains authoritative; Redis is a cache, so correctness doesn’t depend on Redis staying up.
- **Sharding / multi-region:** not implemented here; narrative stops at caching, replicas, and failover. (If we later need global ID allocation across shards, that becomes a coordinated design problem beyond this demo.)

In production we’d monitor Redis hit rate, miss latency, Redis evictions, and Postgres query time so we can resize/tune before cache-miss storms impact the primary.

---
## Collision handling

- **Collisions / uniqueness:** avoided by design today.

  In this demo, Postgres assigns each row a unique primary key `id`. We convert that `id` to Base62 and store it as `slug` (with a `UNIQUE` index on `slug`). Because the `id` cannot repeat, two different links cannot end up with the same short code.

  Also, encoding is naturally safe for duplicates: the `original_url` column is `UNIQUE`, so the same long URL maps to the same record.

- **If we scale writes beyond a single primary DB:** we would need a globally unique ID generator (so every writer can produce a non-colliding `slug`).

  A dedicated “counter service” can work in principle (writers ask for the next counter and then Base62-encode it), but doing it as a single “increment on every request” endpoint can become a bottleneck. In practice, we'd use ID range leasing (allocate a block of IDs to each writer) or switch to a distributed ID scheme (e.g. Snowflake/ULID-style IDs).

---

## Security (risks & mitigations)

| Risk | Mitigation / note |
|------|-------------------|
| **Open redirect abuse** Short links hide destinations (phishing). | Document; restrict schemes (`http`/`https` only) and max URL length in app; future warnings / blocklists. |
| **Enumeration** Low-entropy or guessable codes. | Document; prod: rate limiting, anomaly detection. |
| **DoS** Huge bodies or abusive traffic. | Max length validation; rate limiting at edge in prod. |
| **Injection** Malicious inputs in logs. | Parameterized queries; no server-side fetch of arbitrary URLs (**no SSRF** in this API). |
| **URLs in request logs** | JSON bodies can appear in access or debug logs. Redact or sample in production. |

---

## Testing

- **Request specs** for `/encode` and `/decode`: happy path, idempotent encode, malformed input, 404 decode.
- **Service specs** for decode cache and short-link parsing.

```bash
bundle exec rspec
```

---

## Related docs

- **[SETUP.md](SETUP.md)** — environment, Docker, tests, **Fly.io Redis** (`fly redis create`, `REDIS_URL`, eviction).
- **[ASSIGNMENT_REQUIREMENTS.md](ASSIGNMENT_REQUIREMENTS.md)** — interpreted requirements checklist.
