# URL Shortener — proposed README (draft)

This document is an **alternate README** meant for review alongside `README.md`. It describes how the assignment would be framed after aligning with the brief—PK-based slugs, Redis caching, Postgres as source of truth, and README sections recruiters expect — without requiring every line of code to match yet.

---

## Assignment summary

Small **JSON API**: shorten a long URL and resolve a short URL back to the original. Short codes must remain valid **after app restart** (durable persistence). **Ruby** implementation (Rails API mode suggested).

---

## Tech stack

- **Ruby 3.1.x**, **Rails 7.1.x** (API mode)
- **PostgreSQL**: canonical store for `{ hash_value ↔ original_url }`, unique slug constraint
- **Redis** (target): decode cache (`hash_value` → URL), optional write-through after encode  
- Optional: **Docker** for consistent local/prod-ish runs  
- Tests: **RSpec**

---

## API contract (align with assignment wording)

Prefer routes **exactly** as stated in the brief (confirm with interviewer if ambiguous):

| Method | Path | Request body | Success response |
|--------|------|---------------|-------------------|
| `POST` | `/encode` | `{ "url": "<original>" }` | `{ "shortened_link": "<base>/<slug>" }` (exact key names documented in code + tests) |
| `POST` | `/decode` | `{ "url": "<short-url-or-path>" }` | `{ "original_link": "<url>" }` |

Document **HTTP status codes** for invalid payload, unknown slug, validation errors — and mirror them in request specs.

> **Separate runbook:** the brief asks for detailed run instructions in **another markdown file** (for example `SETUP.md`). This draft keeps README focused on behavior and ops concepts; duplicate minimal quickstart here or split fully into `SETUP.md` after you decide.

---

## Algorithm and uniqueness

**Recommended direction: derive the slug from the database surrogate primary key** (insert row → numeric `id` → Base62). Store the resulting string as `hash_value`.

- **Uniqueness across app servers:** one global namespace enforced by Postgres (`UNIQUE` on `hash_value`). Writes go to the authoritative database; horizontally scaled Rails processes do not “allocate” collisions-prone identifiers in isolation without that constraint.
- **Collisions:** not a meaningful problem vs truncated MD5: each new row gets a new `id`; encoding is injective for stable integer → string mapping.
- **Visual length / small DB row counts:** sequential ids yield short codes early — acceptable for a demo — or optionally **start sequence** at a larger offset (`SETVAL`/`RESTART`), or left-pad to a minimum length — document the trade-off (enumeration / guessability stays similar to sequential slugs unless you introduce opaque tokens).

**Drawback (document honestly):** slugs correlate with insertion order unless you add entropy elsewhere; production mitigations include rate limits, abuse monitoring, longer random tokens — out of minimal assignment scope unless you extend.

---

## Caching (`/decode`) — Postgres + Redis

1. **`GET`** equivalent in Redis: `hash_value` → cached `original_url`.  
2. On miss: load from Postgres (`original_url`), then **populate Redis**.  
3. On **`/encode`** success (after commit): optional **write-through** to Redis so the next decode is fast and avoids read-replica staleness quirks for fresh links.

Treat Redis as **non-authoritative**: if Redis evicts entries or disappears, correctness is unchanged — latency and DB load increase.

---

## Scaling (Rails + Postgres + Redis only — conceptual)

- **Rails:** horizontally scale web processes; workers remain stateless.  
- **Redis:** absorbs read-heavy `/decode` after warm caches.  
- **PostgreSQL:** unique index + primary key indexing on slug; migrate to **read replicas** when cache miss + decode volume exceeds comfortable primary utilization. Writes stay on primary.  
- **Shard / failover (homework-grade notes):** this repo does **not** implement Vitess/sharded topology. Narrative stops at replicas + caching; shard routing and failover are “next evolution” multi-tenant infra, not Rails changes alone.

Rough capacity note optional: reads dominated by Redis; single-region Postgres bottleneck moves to encode rate and replication lag visibility.

---

## Security (risks & mitigations)

Document these even if mitigations are partial in code:

| Risk | Mitigation / note |
|------|-------------------|
| **Open redirect abuse** Short links hide destinations (phishing). | Disclaimer in README; optionally restrict schemes (e.g. `http/https` only), max URL length; future user warnings / blocklists. |
| **Enumeration** Sequential or low-entropy codes are sprayable for discovery. | Document; prod: rate limiting, anomaly detection. |
| **DoS via large payloads** Huge `url` bodies or abusive traffic. | Max length validation, basic rate limiting at edge. |
| **Injection** Malicious inputs in logs or redirects. | AR parameterization already; sanitize display if any UI existed. |
| **SSRF N/A here** Assignment does **not** require fetching URLs server-side — don’t introduce it. |

---

## Testing

- **Request specs** for `/encode` and `/decode`: happy path, duplicates, malformed input, 404 decode.  
- Service/model specs optional for pure logic layers.  

Run: `bundle exec rspec`.

---

## Quick local run (minimal — fuller copy can move to SETUP.md)

```bash
bundle install
rails db:prepare
rails s
```

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

(Update host/slug placeholders to match your deployment.)

---

## Comparison with legacy notes in `README.md`

Older documentation described **MD5(URL + salt) + truncated hex + Base62**. That favors opaque-looking codes at the cost of **collision surface** unless you widen entropy or retry on unique violations.

This draft favors **explainable correctness** (PK-derived slug, unique index) plus **honest drawbacks** — a common interview sweet spot — and aligns **operational storytelling** around **Rails + Postgres + Redis**.

Replace or merge sections from this file after you finalize routes, encoder implementation, Redis wiring, and the separate setup markdown filename.
