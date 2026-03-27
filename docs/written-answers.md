# Written Answers

---

## 1. HIPAA-Compliant Messaging Storage with Unreliable Webhooks

### The Core Problem

GHL webhooks are your only source of message data (no retrieval API due to HIPAA). Webhooks can fail silently — if GHL goes down or a webhook doesn't fire, that message is gone. You need a system that maximizes capture reliability while honestly acknowledging what can't be solved.

### My Approach: Multi-Layer Reliability

#### Layer 1: Bulletproof Webhook Ingestion

The webhook endpoint should do the absolute minimum: validate, store raw, respond.

```
POST /api/webhooks/ghl/message
  1. Validate webhook signature (authenticate it's from GHL)
  2. INSERT raw payload into webhook_events table (status: RECEIVED)
  3. Return 200 OK immediately (< 200ms)
  4. Enqueue async processing job
```

**Why raw-first:** If your processing logic crashes, the message isn't lost — it's in `webhook_events` waiting to be reprocessed. The raw payload is your safety net.

**Key tables:**
- `webhook_events` — Raw payloads, append-only. Columns: `id`, `event_type`, `raw_payload (JSONB)`, `status (RECEIVED/PROCESSED/FAILED)`, `processed_at`, `created_at`, `idempotency_hash`
- `messages` — Processed, structured message data. Columns: `id`, `clinic_id`, `conversation_id`, `ghl_message_id (UNIQUE)`, `sender_type (PATIENT/CLINIC/SYSTEM)`, `content (encrypted)`, `sent_at`, `source (WEBHOOK/MANUAL)`, `created_at`

#### Layer 2: Idempotent Processing

Webhooks can fire multiple times (retries, GHL bugs). The processor must handle this.

```
Process webhook job:
  1. Hash the payload to create idempotency_hash
  2. Check: does this hash already exist in webhook_events? → Skip
  3. Check: does ghl_message_id already exist in messages? → Skip
  4. Extract message fields, encrypt content (AES-256)
  5. INSERT into messages table
  6. UPDATE webhook_events status → PROCESSED
```

**Deduplication at two levels:** payload hash (catches exact duplicates) and `ghl_message_id` (catches retries with slightly different payloads).

#### Layer 3: Gap Detection

You can't retrieve missed messages, but you CAN detect that messages are missing.

- **Sequence monitoring:** Track message timestamps per conversation. If there's an unexpected gap (e.g., 6 hours of silence during business hours), flag it.
- **Webhook heartbeat:** Monitor webhook event frequency per clinic. If a clinic that normally receives 50+ webhooks/day drops to zero, alert immediately — GHL may be down or the webhook URL may have changed.
- **Daily reconciliation:** Compare message counts against any available GHL metadata (e.g., conversation count endpoints, if available without message content).

#### Layer 4: What You CAN'T Solve (and What to Do About It)

If GHL never fires the webhook AND has no retrieval API, the message content is permanently lost to your system. No architecture can recover data that was never transmitted.

**Mitigations:**
- Real-time alerting on gaps (detect within minutes, not hours)
- Escalation playbook: when gap detected → contact GHL support, check webhook config, verify GHL service status
- Manual entry: for known missed messages, allow clinic staff to manually add them (source: MANUAL)
- Contractual: negotiate with GHL for webhook delivery guarantees or a HIPAA-compliant retrieval endpoint

#### HIPAA-Specific Considerations

- **Encryption at rest:** Message content encrypted with AES-256 before storage. Encryption keys managed separately (AWS KMS or similar).
- **Access audit logging:** Every read of message content logged with user ID, timestamp, purpose.
- **Retention policy:** Define retention period, auto-archive or purge after expiry.
- **Minimum necessary:** API endpoints should not return message content by default — only when explicitly requested with audit trail.

---

## 2. Biggest Risks and Architectural Weak Points

Ranked by impact × likelihood:

### 1. GHL as a Single Point of Failure (Critical)

GHL handles contacts, calendars, and messaging. You don't control its availability, its webhook reliability, or its API changes. If GHL goes down, your clinics lose the ability to communicate with patients. If GHL changes their API without notice, your sync layer breaks silently.

**Mitigation:** Abstract GHL behind an adapter pattern. If you need to switch providers (or add a second one), you replace the adapter, not the entire system. Monitor GHL's uptime and webhook delivery rate independently.

### 2. Meta API Rate Limits at Scale (High)

9,000 points/hour with 200+ clinics. Each campaign launch costs ~15 points. Performance syncs cost 3 points each. On a busy day (e.g., Black Friday, clinics launching holiday campaigns), you could hit the limit.

**Mitigation:** Queue-based launch system with rate limit awareness. Performance syncs staggered across the hour. Request higher API tier from Meta as volume justifies it.

### 3. Data Drift Between Local DB and Meta (High)

Meta is the source of truth for campaign status and performance. Your local DB is a cache. If a sync fails or a status change happens on Meta's side (e.g., Meta pauses a campaign for policy violation), your DB shows stale data.

**Mitigation:** Periodic full reconciliation (not just incremental syncs). Campaign detail pages should show `lastSyncedAt` so users know data freshness. Critical status changes (pause, policy violation) should trigger immediate webhook from Meta if available.

### 4. OAuth Token Lifecycle (Medium)

Meta tokens expire. If a token expires and the refresh fails, that clinic's campaigns become unmanageable — can't pause, can't check performance, can't launch new campaigns.

**Mitigation:** Proactive refresh (7 days before expiry). Alert clinic owner if refresh fails. Dashboard indicator showing connection health.

### 5. HIPAA Boundary Creep (Medium)

As the product grows, the line between "clinic marketing data" (not PHI) and "patient data" (PHI) could blur. If AI copy generation ever ingests patient reviews, appointment data, or treatment history, you're in HIPAA violation territory.

**Mitigation:** Hard architectural boundary: AI copy generation has access ONLY to clinic-level data (brand voice, service list, pricing). Never patient-level data. Enforce this with separate database schemas or access controls, not just code conventions.

---

## 3. Relevant Past Projects

*(Note: These should be personalized to your actual experience. Below is a framework for the kinds of projects to highlight.)*

- **Multi-tenant SaaS platforms:** Building shared-database multi-tenant systems with tenant isolation enforced at the middleware layer. Learned that tenant isolation bugs are the most dangerous class of bugs — they silently leak data between customers.

- **Third-party API integrations with webhook ingestion:** Building reliable webhook consumers for payment processors and communication platforms. Developed patterns for idempotent processing, dead letter queues, and reconciliation jobs that I'm applying directly to the GHL integration challenge.

- **Campaign/marketing systems:** Building systems where users configure campaigns, launch them to external platforms, and monitor performance. Learned that the status machine is critical — intermediate states (LAUNCHING, PENDING) prevent duplicate actions and race conditions.

- **PostgreSQL schema design for production systems:** Designing schemas that survived 2+ years of feature growth without major migrations. Key lesson: JSON columns for third-party API data (like Meta's targeting spec) save enormous migration churn vs. normalized tables.

---

## 4. Applicable Patterns from Past Work

### Patterns I'd Reuse

1. **Idempotent webhook handlers:** Always store the raw payload first, process async. Deduplication via payload hash + unique external ID. This pattern saved us multiple times when a payment processor double-fired webhooks.

2. **Status machine with audit log:** Every status change goes through a single function that validates the transition, updates the record, and appends to the audit log atomically. Never update status directly — always through the state machine. This prevented dozens of "how did this campaign end up in this state?" support tickets.

3. **Adapter pattern for third-party services:** Wrap external APIs (GHL, Meta) in a thin adapter with your own interface. When Meta changes their API version, you update one file. When GHL changes their webhook format, you update one parser. The rest of your codebase never knows.

4. **Background job queues for API-bound operations:** Never call external APIs synchronously in a request handler. Queue the work, return immediately, update status via polling or webhook. Users see "launching..." instead of a 30-second loading spinner that might timeout.

### Mistakes I'd Avoid

1. **Trusting webhook delivery:** Early in my career, I assumed webhooks were reliable. They're not. Now I always build detection for "what if this webhook never arrives?"

2. **Storing money as floats:** Learned this the hard way with rounding errors in invoice calculations. Cents as integers, always.

3. **Over-normalizing third-party data:** I once built 12 tables to normalize a payment processor's response format. They changed their API 3 months later and I had to rewrite all 12 tables. JSONB for external API data, normalized tables for your own domain data.

4. **Skipping intermediate states:** Building a system with just "draft" and "active" meant we had no way to prevent duplicate launches or track what was happening during a slow API call. Intermediate states (PENDING_LAUNCH, LAUNCHING) are essential for any system that calls external APIs.
