# Decision Log

Every significant choice made during this assessment, with alternatives considered and reasoning.

---

## Schema Decisions

### 1. Multi-Tenancy: Shared Database with `clinic_id`

**Chose:** Single database, `clinic_id` foreign key on every tenant-scoped table.
**Considered:** Schema-per-tenant, database-per-tenant.
**Why:** With 200+ clinics and growing, schema-per-tenant creates migration complexity (every migration runs 200+ times). Database-per-tenant adds operational overhead. Shared database with proper indexing on `clinic_id` scales well for this size and keeps Prisma's migration story simple.
**Risk:** No hard database-level isolation. A bug in query filtering could leak data between clinics. Mitigation: middleware that injects `clinic_id` filters automatically, never trusting client input for tenant identity.

### 2. Offer Templates: System-Level (No `clinic_id`)

**Chose:** `OfferTemplate` table without `clinic_id` — shared across all clinics.
**Considered:** Per-clinic templates, hybrid (system + clinic templates).
**Why:** Client confirmed templates are system-level. Per-clinic templates would be premature — clinics customize at the `Offer` level, not the template level. If per-clinic templates are needed later, adding a nullable `clinic_id` to the table is a non-breaking change.
**Risk:** Low. System templates are read-only for clinics.

### 3. JSON Columns for Targeting, Placements, and Items

**Chose:** JSONB columns for `audience_targeting`, `placements`, `included_items`, `brand_voice`, `trust_signals`.
**Considered:** Normalized tables for each (e.g., `campaign_targeting_criteria`, `campaign_placements`).
**Why:** Meta's targeting schema is extensive (age, gender, interests, behaviors, geo, custom audiences) and changes frequently. Normalizing would require migration churn every time Meta adds a targeting option. JSONB preserves Meta's native format, supports indexing (`@>` operator), and avoids join overhead. Same logic applies to placements and offer items — these are lists that vary in structure.
**Risk:** No referential integrity within JSON. Mitigation: validate JSON shape at the application layer before write.

### 4. Monetary Values in Cents (Integer)

**Chose:** All prices and budgets stored as `Int` representing cents.
**Considered:** `Decimal` type, `Float`.
**Why:** Float arithmetic causes rounding errors ($19.99 + $0.01 ≠ $20.00 in IEEE 754). Decimal works but adds ORM complexity. Cents-as-integer is the industry standard (Stripe, Meta's API itself uses cents). Simple, precise, no rounding bugs.
**Risk:** Display layer must divide by 100. This is well-understood and trivial.

### 5. Soft Delete via `deleted_at`

**Chose:** Nullable `deleted_at` timestamp on tenant-scoped tables (Clinic, User, Offer, Campaign, Ad).
**Considered:** Hard delete, boolean `is_deleted` flag.
**Why:** Campaigns involve real money. Deleting a campaign record means losing the ability to audit what happened. `deleted_at` timestamp preserves history AND tells you when it was deleted. Boolean flag loses the "when."
**Risk:** Queries must filter `WHERE deleted_at IS NULL` by default. Mitigation: Prisma middleware or default scope.

### 6. Campaign Status as Enum State Machine

**Chose:** `CampaignStatus` enum with 8 states: DRAFT → PENDING_LAUNCH → LAUNCHING → ACTIVE → PAUSED/COMPLETED/CANCELLED. Any state → FAILED.
**Considered:** Simple statuses (DRAFT/ACTIVE/INACTIVE), free-form string.
**Why:** The campaign lifecycle has clear states with specific allowed transitions. An enum enforces valid values at the database level. The PENDING_LAUNCH and LAUNCHING intermediate states are critical — they prevent a campaign from being launched twice if the user double-clicks or retries during a slow Meta API call.
**Risk:** Adding new states requires a migration. Acceptable tradeoff for data integrity.

### 7. CampaignConfig as Separate Table (1:1)

**Chose:** Separate `CampaignConfig` table with `campaign_id UNIQUE`.
**Considered:** Embedding config columns directly in `Campaign`.
**Why:** Three reasons: (1) Config maps to a different Meta entity (Ad Set), keeping them separate mirrors Meta's hierarchy. (2) Campaign has 15+ columns already — adding 8 more config columns creates a wide table that's hard to reason about. (3) Config is updated independently from campaign metadata (e.g., adjusting budget without changing campaign name).
**Risk:** Extra join on campaign detail queries. Minimal performance impact with proper indexing.

### 8. Denormalized `clinic_id` on Campaign

**Chose:** `clinic_id` on Campaign table even though it's derivable via Campaign → Offer → Clinic.
**Considered:** Only storing `clinic_id` on Offer, joining through.
**Why:** Campaign is the most-queried table for dashboard filtering ("show me all active campaigns for this clinic"). A direct `clinic_id` with a composite index `(clinic_id, status)` avoids a join through Offers on every dashboard load. The denormalization is worth it for query performance.
**Risk:** Data inconsistency if Campaign's `clinic_id` differs from Offer's. Mitigation: set `clinic_id` from Offer at creation time, never allow updates.

### 9. Ad Angles Embedded in Ad (Not Separate Table)

**Chose:** `angle_type` and `angle_name` as columns on `Ad`, rather than a separate `AdAngle` table.
**Considered:** Separate `AdAngle` table with 1:1 relationship to `Ad`.
**Why:** In the current design, an angle IS an ad — each angle produces exactly one ad. A separate table adds a join without adding value. If angles needed to be reused across campaigns, a separate table would make sense, but the brief doesn't indicate that.
**Risk:** If angles need metadata beyond type + name, the Ad table gets wider. Acceptable for current scope.

### 10. Meta IDs as Nullable Strings

**Chose:** `meta_campaign_id`, `meta_ad_set_id`, `meta_ad_id`, `meta_creative_id` as nullable `String` fields.
**Considered:** Required fields, separate `meta_references` table.
**Why:** These fields are null before launch and populated after. Making them required would mean campaigns can't be saved as drafts. A separate table adds complexity for what's essentially a 1:1 extension. Nullable strings are the simplest correct approach.
**Risk:** Code must null-check before any Meta API operation. This is the correct behavior — you should verify Meta IDs exist before managing a campaign.

### 11. Idempotency Key on Campaign

**Chose:** `idempotency_key` unique column on Campaign.
**Considered:** Separate idempotency table, no idempotency.
**Why:** The launch endpoint calls Meta's API to create real campaigns that spend real money. Network timeouts or user retries could create duplicates. The idempotency key (generated client-side, checked server-side) prevents this. On Campaign table rather than separate table because the key is meaningful only in the campaign context.
**Risk:** Client must generate and send the key. Standard pattern.

### 12. Append-Only Audit Tables

**Chose:** Two separate log tables: `CampaignStatusLog` (status changes) and `MetaSyncLog` (raw API responses).
**Considered:** Single `audit_log` table, no logging.
**Why:** Separation because they serve different purposes. Status log answers "what happened to this campaign and who did it" — for users and compliance. Sync log answers "what did Meta's API actually return" — for debugging. Combining them would mean filtering noise constantly. Both are append-only (never updated/deleted) for audit integrity.
**Risk:** Log tables grow indefinitely. Mitigation: partition by date, archive old records.

---

## API Decisions

### 13. Nested Resource URLs

**Chose:** `/api/offers/:offerId/campaigns` for campaigns under offers.
**Considered:** Flat `/api/campaigns?offerId=uuid`.
**Why:** The nesting reflects the domain hierarchy — a campaign always belongs to an offer. It prevents creating a campaign without an offer context. It also makes the URL self-documenting. Ads are under campaigns for the same reason.
**Risk:** Deeper nesting (3+ levels) gets unwieldy. We stop at 2 levels — campaigns are also accessible directly where needed (e.g., `/api/campaigns/:id/ads`).

### 14. Launch as Action Endpoint (POST, Not PATCH)

**Chose:** `POST /campaigns/:id/launch` instead of `PATCH /campaigns/:id { status: "ACTIVE" }`.
**Considered:** PATCH status field, PUT to lifecycle endpoint.
**Why:** Launch isn't a simple field update — it triggers a multi-step workflow (validate → call Meta API → create campaign → create ad set → create ads → update local records). Modeling it as a PATCH obscures the complexity and side effects. POST to an action endpoint makes it explicit: "this does something beyond updating a row."
**Risk:** More endpoints to maintain. Worth it for clarity.

### 15. Cursor-Based Pagination

**Chose:** Cursor-based pagination (`?cursor=<last_id>&limit=20`).
**Considered:** Offset-based (`?page=1&limit=20`).
**Why:** Offset pagination breaks when records are inserted or deleted between page loads — you get duplicates or skip items. Cursor pagination is stable regardless of concurrent writes. This matters when multiple team members at a clinic are creating campaigns simultaneously.
**Risk:** Can't jump to "page 5." This is rarely needed in a dashboard context.

### 16. Clinic ID from JWT (Never in URL)

**Chose:** Extract `clinic_id` from JWT claims in auth middleware.
**Considered:** `clinic_id` as URL parameter or request body field.
**Why:** If `clinic_id` is in the URL, a client bug or malicious request could access another clinic's data. By deriving it from the JWT, tenant isolation is enforced at the middleware level — individual endpoint handlers can't accidentally forget to filter. This eliminates an entire class of security bugs.
**Risk:** None. This is a strict improvement over URL-based tenant identification.

---

## Integration Decisions

### 17. Raw HTTP Instead of Meta's Node.js SDK

**Chose:** Raw `fetch` calls to Meta's Graph API.
**Considered:** `facebook-nodejs-business-sdk` npm package.
**Why:** For this POC: (1) shows understanding of the actual API, not just an SDK wrapper; (2) Meta's SDK is poorly typed and heavy (100+ MB); (3) raw calls are easier to debug and explain; (4) the POC only needs 4 endpoints — a full SDK is overkill. In production, a thin custom client (like this POC's `meta-api-client.ts`) is preferable to the SDK anyway.
**Risk:** Must handle HTTP details manually. For 4 endpoints, this is trivial.

### 18. Sequential Meta API Calls (Not Parallel)

**Chose:** Create Campaign → then Ad Set → then Ad Creative + Ad, sequentially.
**Considered:** Parallel creation of Ad Set and Ads.
**Why:** Meta's hierarchy is strict: Ad Set needs Campaign ID, Ad needs Ad Set ID and Creative ID. The dependency chain is linear. Ad Creatives could theoretically be created in parallel, but the complexity isn't worth saving ~200ms on 2-3 API calls.
**Risk:** Slower for campaigns with many ads. At 3 ads, total time is ~2-3 seconds. Acceptable.

### 19. All Entities Created as PAUSED

**Chose:** Create every Meta entity with `status: PAUSED`.
**Considered:** Create as ACTIVE immediately.
**Why:** Creating as ACTIVE would start spending money the moment the API call succeeds — before the user can verify everything is correct on Meta's side. PAUSED lets us create the full structure, verify it, then activate. Also prevents accidental spend during testing.
**Risk:** Requires a separate activation step after launch. In the current flow, the launch endpoint would set status to ACTIVE after all entities are created successfully.

---

## Beyond the Brief

### 20. GHL Webhook Reliability

**Observation:** GHL is a single point of failure for messaging data. Webhooks have no delivery guarantee, and there's no retrieval API (HIPAA restriction). If a webhook fails, that message is permanently lost.
**Impact:** The messaging storage system must be designed for maximum reliability: immediate ACK + async processing, raw payload storage, gap detection monitoring.
**Recommendation:** See written answers for full design. Long-term, evaluate whether GHL's HIPAA limitations warrant migrating to a platform with a message retrieval API.

### 21. Meta Token Refresh Strategy

**Observation:** Meta OAuth tokens expire. The schema stores `token_expires_at`, but there's no mention of a refresh strategy in the brief.
**Impact:** A silently expired token means campaigns can't be launched or managed. Users wouldn't know until they try.
**Recommendation:** Background job that checks token expiry daily, triggers refresh 7 days before expiration, alerts clinic owners if refresh fails.

### 22. Rate Limiting at Scale

**Observation:** Meta's API allows 9,000 points/hour (standard tier). Each campaign launch is ~15 points (5 API calls × 3 points). With 200+ clinics, a busy launch day could exhaust the limit.
**Impact:** Rate limit errors during launch would fail campaigns unpredictably.
**Recommendation:** Implement a launch queue. Instead of calling Meta synchronously in the launch endpoint, queue the launch and process sequentially with rate limit awareness. Return `202 Accepted` and update status via webhook/polling.

### 23. HIPAA Boundary for Ad Data

**Observation:** ForeverBooked is HIPAA-compliant, handling medical spa data. Ad copy generated from clinic data (brand voice, procedures) could inadvertently include protected health information.
**Impact:** If patient-specific data leaks into ad copy (e.g., AI trained on patient reviews), it could violate HIPAA.
**Recommendation:** AI copy generation should NEVER have access to patient data. Strictly limit AI context to clinic-level data (brand voice, procedures offered, pricing). Add guardrails in the prompt/API layer.
