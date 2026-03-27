# ForeverBooked — Backend Developer Assessment

Backend design and proof-of-concept for the Meta Ads campaign launcher feature.

## Quick Links

| Deliverable | Location |
|---|---|
| Database Schema (Prisma) | [`prisma/`](prisma/) — multi-file: schema.prisma + schema/ (clinic, offer, campaign, audit) |
| Database Schema (SQL DDL) | [`sql/schema.sql`](sql/schema.sql) |
| Schema ERD Diagram | [`diagrams/schema-erd.md`](diagrams/schema-erd.md) |
| API Design | [`docs/api-design.md`](docs/api-design.md) |
| Decision Log | [`docs/decision-log.md`](docs/decision-log.md) |
| Written Answers | [`docs/written-answers.md`](docs/written-answers.md) |
| Meta Integration POC | [`src/`](src/) |

## Project Structure

```
├── prisma/
│   ├── schema.prisma               # Generator, datasource, shared enums
│   └── schema/
│       ├── clinic.prisma           # Clinic, User, MetaOAuthToken
│       ├── offer.prisma            # OfferTemplate, Offer
│       ├── campaign.prisma         # Campaign, CampaignConfig, Ad, AdMedia
│       └── audit.prisma            # CampaignStatusLog, MetaSyncLog
├── prisma.config.ts                # Prisma 7 config (schema path, datasource, migrations)
├── sql/
│   └── schema.sql                  # PostgreSQL DDL with indexes and constraints
├── src/
│   ├── constants.ts                # Application-wide constants
│   ├── helpers.ts                  # Shared utility functions
│   ├── types.ts                    # Domain types mirroring Prisma schema
│   ├── meta-http-post.ts           # Raw HTTP helper for Meta Graph API
│   ├── meta-api-client.ts          # Campaign, Ad Set, Ad Creative, Ad creation
│   └── create-campaign.ts          # Main entry — launches full campaign structure
├── docs/
│   ├── api-design.md               # RESTful /api/v1/ endpoints with request/response shapes
│   ├── decision-log.md             # 23 decisions with alternatives and reasoning
│   └── written-answers.md          # HIPAA messaging, risks, experience, patterns
└── diagrams/
    └── schema-erd.md               # Mermaid ERD diagram
```

## Meta Integration POC

### Prerequisites

- Node.js 18+ (for native `fetch`)
- Docker Desktop (for local PostgreSQL)
- A Meta Developer account with a **Business Portfolio** containing:
  - A Facebook Page connected to the ad account
  - An ad account with a payment method attached
  - A Meta app with Marketing API use case enabled
- Access token with permissions: `ads_management`, `ads_read`, `pages_read_engagement`, `pages_show_list`, `pages_manage_ads`

### Setup

```bash
# Install dependencies
npm install

# Start local PostgreSQL (port 4040)
npm run db:up

# Copy env file and fill in your credentials
cp .env.example .env
# Edit .env: META_ACCESS_TOKEN, META_AD_ACCOUNT_ID (act_XXX), META_PAGE_ID

# Run Prisma migration
npm run db:migrate

# Run the POC
npm run poc
```

### What It Does

Creates a complete campaign structure in Meta's sandbox:

```
Offer: "Spring Botox Special" ($199)
  └── Campaign (OUTCOME_AWARENESS, status=PAUSED)
        └── Ad Set (budget in account currency, US, ages 25-55)
              ├── Ad: Social Proof   → "Join 500+ Happy Clients"
              ├── Ad: Pain Point     → "Tired of Fine Lines?"
              └── Ad: Urgency        → "Limited: Spring Special Ending Soon"
```

All resources are created with `status=PAUSED` to prevent accidental spend.

### Domain → Meta Mapping

| ForeverBooked | Meta Entity | Notes |
|---|---|---|
| Offer | — | Parent context, not a Meta entity |
| Campaign + Objective | Campaign | `special_ad_categories: []` required even if empty |
| CampaignConfig (budget, targeting) | Ad Set | `daily_budget` in cents, minimum $5/day |
| Ad (angle copy + media) | Ad Creative + Ad | Each angle = one creative + one ad |

### Meta API Notes

- **API Version:** v25.0
- **Auth:** Form-encoded POST with `access_token` parameter (no OAuth flow in POC)
- **`special_ad_categories`**: Must be included even when empty — omitting causes rejection
- **Budget**: Integer in the ad account's currency smallest unit. Minimum varies by currency (e.g. đ26,445 for VND). Set `dailyBudget` in `create-campaign.ts` to match your account's currency
- **All resources PAUSED**: Prevents accidental spend during testing
- **Error format**: Meta returns `{ error: { message, type, code, error_subcode } }`

## Schema Highlights

- **Multi-tenant**: Shared database, `clinic_id` on every tenant-scoped table
- **Multi-file Prisma schema**: Split by domain (clinic, offer, campaign, audit) — Prisma v7+ native support
- **12 models, 7 enums**: Full coverage of the campaign launcher feature
- **Audit trail**: Append-only `CampaignStatusLog` for full campaign history reconstruction
- **JSON columns**: For Meta targeting spec, placements, offer items — avoids migration churn when Meta's API evolves
- **Money in cents**: Integer, not float. Industry standard (Stripe, Meta both use cents)

## Key Design Decisions (Summary)

See [`docs/decision-log.md`](docs/decision-log.md) for full details on all 23 decisions. Highlights:

1. **Shared DB multi-tenancy** — simpler than schema-per-tenant for 200+ clinics
2. **CampaignConfig as separate table** — mirrors Meta's Campaign/Ad Set split
3. **Idempotency key on launch** — prevents duplicate Meta campaigns on retry
4. **Raw HTTP over Meta SDK** — shows API understanding, lighter, better typed
5. **8-state campaign lifecycle** — intermediate states (LAUNCHING) prevent race conditions
6. **API versioning (`/api/v1/`)** — supports non-breaking API evolution
