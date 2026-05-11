# URL shortener assignment — requirements (interpretation for handoff)

This document states how the brief is **understood** for implementation and review. **Verify** any item marked *assumption* or *confirm with reviewer* against the official assignment text.

---

## Goal

Build a **ShortLink**-style service: given a long URL, return a short URL; given that short URL, recover the original URL. Responses are **JSON**. The service must **remember** mappings **across process restarts** (durable persistence).

---

## Technical constraints

| Item | Requirement |
|------|-------------|
| Language | **Ruby** |
| Framework | Not mandated; **Rails API** is a reasonable fit and matches existing repo |
| Persistence | Mappings must survive **application restart** (database or equivalent durable store) |
| “Scalable service” | **Not** required to build; **document** scalability/collision thinking in **README** |

---

## Functional requirements

### Encoding (`/encode`)

- **Input:** A request representing the **original URL** to shorten (exact parameter name is an *assumption* — typical: `url` in JSON).
- **Output:** JSON including a **short URL** (or equivalent field) that points to this deployment’s host/path and identifies the created short code.
- **Behavior:** A round-trip must work: encode → then decode → **same** original URL.

*Assumption (common product expectation):* Submitting the **same** original URL again **may** return the **same** existing short URL (idempotent / deduplicated). If reviewers prefer a new short URL every time, they must say so (*confirm with reviewer*).

### Decoding (`/decode`)

- **Input:** A request carrying either the **full short URL** or enough to extract the **short code** (implementation choice; document in API section).
- **Output:** JSON including the **original URL**.

### Route paths

- **Official brief** typically names **`/encode`** and **`/decode`**.
- Implementations sometimes use **`/urls/encode`** and **`/urls/decode`**. Either is defensible if documented; this repo uses **`POST /encode`** and **`POST /decode`** with JSON bodies and JSON responses.

---

## Non-functional requirements

### API format

- **JSON** request and response for both endpoints.
- **Define and document** field names, success/error status codes, and error body shape (unless reviewer supplies a strict contract).

### Tests

- **Tests for both endpoints** — in practice interpreted as: automated tests that exercise the **HTTP layer** for encode and decode (e.g. RSpec **request specs**), including at least success paths; ideally invalid input and not-found decode.
- **Other tests** (models, services) are optional but encouraged.

### Documentation

| Deliverable | Requirement |
|-------------|-------------|
| **README.md** | Security: **identify attack/abuse angles**; mitigate where cheap **or** document mitigations. Scalability: especially **collision** strategy and how you’d evolve past a single DB — **documentation**, not necessarily full distributed implementation. |
| **Separate markdown file** | **Detailed instructions to run** the assignment (environment, DB, commands, sample curls). Filename e.g. `SETUP.md` (*exact name not specified in brief*). |

### Evaluation themes (from rubric)

- Ruby / Rails practices  
- Correct `/encode` and `/decode` behavior and JSON  
- Completeness (features + tests running)  
- Sensible behavior  
- Maintainable structure  
- Security awareness (documented / mitigated)  
- Scalability awareness (documented, collision addressed honestly)  

### Security / scalability depth

- **Interpretation:** Thoughtful **README discussion** and minimal **reasonable** safeguards in code (e.g. validation, uniqueness index) satisfy the spirit; **full production** hardening (global rate limiting, WAF, full sharding) is **not** implied by the brief. *Confirm with reviewer* if uncertain.

---

## Suggested implementation notes (non-binding)

- **Uniqueness of short codes:** A **database unique constraint** on the short code (slug) is the standard way to enforce global uniqueness on one node; explain **multi-server** as shared DB or documented future step.
- **Collision avoidance:** **Surrogate primary key → Base62 (or similar)** is easy to justify as collision-free per row; document **enumeration** / guessability as a drawback. Alternative: random slug + unique index + retry.
- **Caching (optional improvement):** **Redis** for decode path with Postgres as source of truth; Redis is cache-only.
- **Do not** introduce server-side fetching of arbitrary URLs (SSRF) unless required — not part of typical encode/decode API.

---

## Out of scope (unless explicitly added)

- Full highly available multi-region design  
- Payment, user accounts, analytics — unless assignment extends  

---

## Open questions (*for reviewer or product owner*)

1. Exact paths: strict `/encode` `/decode` vs nested under `/urls/...`  
2. JSON field names and error schema  
3. Idempotent encode for duplicate original URL vs new slug every time  
4. Whether security/scalability expectations are **documentation-first** only  

---

## Acceptance checklist (for verification)

- [ ] Ruby app runs per **SETUP** (or equivalent) doc  
- [ ] `POST` encode returns JSON with a short link; `POST` decode returns JSON with the original URL  
- [ ] Restart app/DB container: **decode still works** for previously encoded URLs  
- [ ] Automated tests cover **encode and decode endpoints** at HTTP level  
- [ ] README covers **security** and **scalability + collisions**  
- [ ] **Separate** markdown file with **run instructions**  

---

## Document control

- **Source of truth:** The official assignment PDF/page from the employer.  
- This file is a **working interpretation** for agents and implementers; reconcile discrepancies with the official brief.
