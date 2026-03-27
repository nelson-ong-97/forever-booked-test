# ForeverBooked — API Design

## Overview

RESTful API for the Meta Ads campaign launcher. Covers the full lifecycle: create offers → build campaigns → launch to Meta → manage post-launch.

### Design Principles

- **Multi-tenant isolation**: `clinic_id` extracted from JWT auth token, never passed in URL. Every query filters by clinic.
- **Consistent errors**: All errors return `{ error: string, code: string, details?: object }` with appropriate HTTP status.
- **API versioning**: All endpoints prefixed with `/api/v1/`. Versioning allows non-breaking evolution of the API as the product grows.
- **Cursor pagination**: List endpoints use `?cursor=<id>&limit=20`. Cursor-based avoids offset drift when data changes.
- **Idempotency**: Mutation endpoints accept `Idempotency-Key` header. Critical for the launch endpoint to prevent duplicate Meta campaigns.

### Authentication

JWT bearer token in `Authorization` header. Token payload includes `clinic_id` and `user_id`. Middleware extracts these and injects into request context. No clinic_id ever appears in request body or URL parameters — this eliminates an entire class of tenant isolation bugs.

---

## Endpoints

### 1. Offer Templates

System-level templates, shared across all clinics.

#### `GET /api/v1/offer-templates`

List available templates. No auth required (system-level data).

**Response:**
```json
{
  "data": [
    {
      "id": "uuid",
      "name": "Botox Special",
      "category": "Injectables",
      "defaultPrice": 19900,
      "defaultItems": ["20 units Botox", "Free consultation"]
    }
  ]
}
```

---

### 2. Offers

Clinic-specific offers. `clinic_id` always comes from auth context.

#### `GET /api/v1/offers`

List clinic's offers. Supports `?status=active` filter and cursor pagination.

**Response:**
```json
{
  "data": [{ "id": "uuid", "name": "Spring Botox Special", "price": 19900, "campaignCount": 2 }],
  "cursor": "next-page-id"
}
```

#### `POST /api/v1/offers`

Create an offer, optionally from a template.

**Request:**
```json
{
  "name": "Spring Botox Special",
  "price": 19900,
  "includedItems": ["20 units Botox", "Free consultation"],
  "scarcityDetail": "Only 10 spots available this month",
  "templateId": "uuid-optional"
}
```

**Why `templateId` is optional**: Clinics can create offers from scratch or use a template as a starting point. If `templateId` is provided, the template's defaults pre-fill any fields not explicitly set.

**Response:** `201 Created` with the full offer object.

#### `GET /api/v1/offers/:id`

Get offer with summary of its campaigns.

#### `PATCH /api/v1/offers/:id`

Update offer fields. Only allowed when no campaigns are in `ACTIVE` status (changing an offer mid-campaign would create inconsistency between our data and what's live on Meta).

#### `DELETE /api/v1/offers/:id`

Soft-delete. Returns `409 Conflict` if offer has active campaigns.

---

### 3. Campaigns

Nested under offers because a campaign always belongs to an offer. This enforces the domain relationship in the URL structure.

#### `POST /api/v1/offers/:offerId/campaigns`

Create a campaign with its config and ad angles in a single request. One request instead of three separate ones because these are always created together — splitting them would mean partial campaign states in the database.

**Request:**
```json
{
  "name": "Spring 2026 Botox Campaign",
  "objective": "LEADS",
  "config": {
    "budgetType": "DAILY",
    "budgetAmount": 2000,
    "audienceTargeting": {
      "age_min": 25,
      "age_max": 55,
      "genders": [2],
      "geo_locations": { "countries": ["US"] }
    },
    "placements": ["facebook_feed", "instagram_feed", "instagram_stories"],
    "scheduleStart": "2026-04-01T00:00:00Z",
    "scheduleEnd": "2026-04-30T23:59:59Z"
  },
  "angles": [
    { "angleType": "SOCIAL_PROOF", "angleName": "Social Proof Angle" },
    { "angleType": "PAIN_POINT", "angleName": "Pain Point Angle" },
    { "angleType": "URGENCY_SCARCITY", "angleName": "Urgency Angle" }
  ]
}
```

**Response:** `201 Created` with full campaign, config, and ad stubs (copy fields null until AI generation).

#### `GET /api/v1/offers/:offerId/campaigns/:id`

Returns campaign with config, all ads (with media), and latest status log entry.

**Response:**
```json
{
  "id": "uuid",
  "name": "Spring 2026 Botox Campaign",
  "status": "DRAFT",
  "objective": "LEADS",
  "metaCampaignId": null,
  "config": { "budgetType": "DAILY", "budgetAmount": 2000, "..." : "..." },
  "ads": [
    {
      "id": "uuid",
      "angleType": "SOCIAL_PROOF",
      "headline": "Join 500+ Happy Clients",
      "primaryText": "Our clients love their results...",
      "media": [{ "mediaUrl": "https://...", "mediaType": "IMAGE" }],
      "metaAdId": null
    }
  ],
  "launchedAt": null
}
```

#### `PATCH /api/v1/offers/:offerId/campaigns/:id`

Update campaign name, objective, or config. Only when `status = DRAFT`.

---

### 4. Campaign Actions

Action endpoints use `POST` (not PATCH) because they trigger side effects (Meta API calls, status transitions). They're not simple field updates — they're commands.

#### `POST /api/v1/offers/:offerId/campaigns/:id/launch`

**The most critical endpoint.** Sends everything to Meta and creates the campaign in the clinic's connected ad account.

**Request:**
```json
{
  "idempotencyKey": "client-generated-uuid"
}
```

**Server-side flow:**
1. Validate `status = DRAFT` or `FAILED` (allow retry)
2. Validate clinic has valid, non-expired Meta OAuth token
3. Validate at least 1 ad has headline + primaryText + media
4. Set status to `PENDING_LAUNCH`, log status change
5. Set status to `LAUNCHING`
6. Create Campaign in Meta API → store `metaCampaignId`
7. Create Ad Set in Meta API → store `metaAdSetId`
8. For each Ad: Create Ad Creative + Ad in Meta → store `metaAdId`, `metaCreativeId`
9. Set status to `ACTIVE`, log status change
10. Return campaign with all Meta IDs

**On failure at any step:**
- Set status to `FAILED` with `errorMessage` from Meta
- Store any partial Meta IDs (for cleanup/retry)
- Log to `MetaSyncLog` with full error response
- Return `500` with error details

**Idempotency**: If `idempotencyKey` matches an existing campaign that's `ACTIVE`, return that campaign (don't create a duplicate on Meta). If it matches a `FAILED` campaign, allow retry.

**Response:** `200 OK` with full campaign including Meta IDs.

#### `POST /api/v1/offers/:offerId/campaigns/:id/pause`

Pause an `ACTIVE` campaign. Calls Meta API to pause, then updates local status.

**Response:** `200 OK` with updated campaign.

#### `POST /api/v1/offers/:offerId/campaigns/:id/resume`

Resume a `PAUSED` campaign. Only valid transition from `PAUSED → ACTIVE`.

#### `POST /api/v1/offers/:offerId/campaigns/:id/cancel`

Permanently cancel. Calls Meta API to delete/archive the campaign. Status → `CANCELLED`. This is irreversible.

---

### 5. Ads

#### `GET /api/v1/campaigns/:campaignId/ads`

List all ads for a campaign with their media.

#### `PATCH /api/v1/campaigns/:campaignId/ads/:id`

Update ad copy or attach media. Only when campaign `status = DRAFT`.

**Request:**
```json
{
  "headline": "Updated Headline",
  "primaryText": "Updated body copy...",
  "ctaType": "BOOK_NOW"
}
```

#### `POST /api/v1/campaigns/:campaignId/ads/:id/media`

Upload media to an ad. Accepts multipart/form-data.

**Request:** `multipart/form-data` with `file` field + `mediaType` (IMAGE/VIDEO).

**Response:** `201 Created` with media object including URL.

---

### 6. AI Copy Generation

#### `POST /api/v1/campaigns/:campaignId/generate-copy`

Generate AI ad copy for all angles in a campaign. Uses clinic's `brandVoice` and `trustSignals` plus offer details as context.

**Note:** This is a stub in the POC. In production, this calls an external LLM API.

**Response:**
```json
{
  "ads": [
    {
      "adId": "uuid",
      "angleType": "SOCIAL_PROOF",
      "generatedCopy": {
        "headline": "Join 500+ Happy Clients",
        "primaryText": "Our clients love their results. See why...",
        "description": "Book your consultation today"
      }
    }
  ]
}
```

---

### 7. Campaign Performance

#### `GET /api/v1/campaigns/:campaignId/performance`

Returns synced performance metrics from Meta. Data is fetched periodically by a background job and cached locally.

**Response:**
```json
{
  "campaignId": "uuid",
  "metrics": {
    "spend": 4523,
    "impressions": 12450,
    "clicks": 234,
    "conversions": 18,
    "ctr": 1.88,
    "cpc": 1932
  },
  "lastSyncedAt": "2026-04-05T14:30:00Z"
}
```

**Why cached locally vs. real-time**: Meta's API has rate limits (9,000 points/hour). With 200+ clinics, polling Meta on every dashboard load would exhaust the limit quickly. Instead, a background job syncs performance data every 15-30 minutes.

---

### 8. Meta Connection

#### `GET /api/v1/meta/auth-url`

Generate OAuth URL for clinic to connect their Meta ad account.

**Response:** `{ "authUrl": "https://www.facebook.com/v21.0/dialog/oauth?..." }`

#### `POST /api/v1/meta/callback`

Handle OAuth callback. Exchange code for tokens, store encrypted in `MetaOAuthToken`.

#### `GET /api/v1/meta/status`

Check if clinic has a valid, non-expired Meta connection.

**Response:**
```json
{
  "connected": true,
  "adAccountId": "act_123456",
  "tokenExpiresAt": "2026-05-01T00:00:00Z",
  "needsRefresh": false
}
```

---

## Error Response Format

All errors follow this shape:

```json
{
  "error": "Human-readable error message",
  "code": "CAMPAIGN_NOT_DRAFT",
  "details": {
    "currentStatus": "ACTIVE",
    "allowedStatuses": ["DRAFT", "FAILED"]
  }
}
```

Common error codes:
| Code | HTTP Status | When |
|------|-------------|------|
| `CAMPAIGN_NOT_DRAFT` | 409 | Trying to edit/launch a non-draft campaign |
| `META_NOT_CONNECTED` | 403 | No valid Meta OAuth token for clinic |
| `META_TOKEN_EXPIRED` | 403 | Meta token needs refresh |
| `META_API_ERROR` | 502 | Meta API returned an error |
| `DUPLICATE_LAUNCH` | 409 | Idempotency key already used for active campaign |
| `INSUFFICIENT_ADS` | 422 | Campaign has no ads with complete copy + media |
| `OFFER_HAS_ACTIVE_CAMPAIGNS` | 409 | Cannot delete offer with active campaigns |
