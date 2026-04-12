# Forever Booked — Contact Center Backend

Multi-tenant SaaS backend for medical/aesthetic clinic contact centers. Unified inbox with SMS, calling, and follow-up cadence engine.

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | NestJS 10 + TypeScript (strict mode) |
| ORM | Prisma + PostgreSQL |
| Queue | BullMQ + Redis (@nestjs/bull) |
| Real-time | NestJS WebSocket Gateway + Socket.io + Redis pub/sub |
| Auth | Better Auth (Organizations plugin) |
| Hosting | Railway (PostgreSQL + Redis + NestJS) |
| Storage | Railway Storage Buckets (S3-compatible) |
| SMS/Voice | Twilio (SMS + WebRTC calling + recording) |
| Email | Mailgun (transactional) |
| AI | Anthropic Claude API |
| Billing | Stripe (subscription + metered rebilling) |
| Monitoring | Sentry (errors) + PostHog (product analytics) |

## Getting Started

### Prerequisites

- Node.js 20+
- Docker Desktop (for local PostgreSQL + Redis)
- Twilio account (test credentials for dev)
- Better Auth configured

### Setup

```bash
# Clone and install
git clone <repo-url>
cd forever-booked-api
npm install

# Environment
cp .env.example .env
# Fill in: DATABASE_URL, REDIS_URL, TWILIO_*, BETTER_AUTH_*, SENTRY_DSN, POSTHOG_KEY

# Database
npx prisma migrate dev
npx prisma generate

# Run
npm run start:dev
```

### Run Commands

```bash
npm run start:dev          # Development server (hot reload)
npm run build              # Production build
npm run lint               # ESLint check
npm run test               # Unit tests (no DB required)
npm run test:e2e           # Integration tests (needs test DB)
npm run test:isolation     # Tenant isolation tests (CI-blocking)
npm run test:cov           # Coverage report
npx prisma migrate dev     # Run pending migrations
npx prisma studio          # Visual database browser
```

## Architecture

3-layer pattern: **Controller** (HTTP only) -> **Service** (all logic) -> **Model** (Prisma schema)

```
React Frontend (Vercel)
        |
        v
NestJS API (Railway)  -->  PostgreSQL + Redis (Railway)
        |
        +-- Twilio (SMS + Voice)
        +-- Mailgun (Email)
        +-- Anthropic (AI)
        +-- Stripe (Billing)
        +-- Railway Storage Buckets (Storage)
```

Multi-tenancy: shared database with `tenant_id` on every table + Row Level Security (RLS) + TenantGuard middleware. Belt-and-suspenders isolation.

API: `/api/v1` prefix, cursor-based pagination, Swagger at `/api/docs`.

See [docs/system-architecture.md](docs/system-architecture.md) for full details.

## Project Structure

```
src/
  app.module.ts
  main.ts
  common/           # Guards, interceptors, filters, decorators, shared DTOs
  config/            # Environment validation (Zod)
  prisma/            # PrismaModule + PrismaService (global)
  auth/              # Better Auth integration
  tenant/            # TenantGuard, TenantContext, @Tenant() decorator
  contacts/          # Contact CRUD + custom fields + search
  conversations/     # Conversation threading
  messages/          # Message storage + send
  cadence/           # Follow-up state machine + scheduler
  calls/             # WebRTC calling + recording
  webhooks/          # Queue-first Twilio webhook processing
  notifications/     # Lead alerts (email + SMS)
  integrations/      # External provider adapters (Twilio, Mailgun, Anthropic)
  billing/           # Stripe integration (v1.5)
  gateway/           # WebSocket gateway + Redis pub/sub
prisma/
  schema.prisma      # Database schema (source of truth)
  migrations/
test/
  *.e2e-spec.ts      # Integration tests
  tenant-isolation.e2e-spec.ts  # Cross-tenant isolation (CI-blocking)
```

Each module follows: `module.ts`, `controller.ts`, `service.ts`, `service.spec.ts`, `dto/`

See [docs/project-structure.md](docs/project-structure.md) for full details.

## Documentation

| Document | Purpose |
|---|---|
| [docs/system-architecture.md](docs/system-architecture.md) | Architecture overview, data flows, multi-tenancy |
| [docs/code-standards.md](docs/code-standards.md) | NestJS coding standards, 3-layer pattern, naming |
| [docs/api-conventions.md](docs/api-conventions.md) | REST conventions, /api/v1, pagination, error format |
| [docs/api-design.md](docs/api-design.md) | API endpoint catalog (all routes) |
| [docs/testing-standards.md](docs/testing-standards.md) | Testing strategy, spec files, tenant isolation |
| [docs/project-structure.md](docs/project-structure.md) | Folder layout, module organization |

## Development Workflow

Each Linear ticket = one branch = one PR:

```
1. Pick next unblocked ticket from Linear
2. Create branch: git checkout -b FOR-5-setup-nestjs-scaffold
3. Implement ONLY what the ticket describes
4. Write .spec.ts tests for new services
5. npm run lint && npm run test
6. PR to main -> CI checks (lint + typecheck + tests)
7. Merge -> Linear auto-closes ticket -> Slack notified
8. Next ticket
```

Branch format: `FOR-{N}-{description}` (auto-links to Linear via GitHub integration)

## Implementation Plan

8 phases, 92 tickets, 12-week timeline to first pilot clinic:

| Phase | Weeks | What |
|---|---|---|
| 1. Foundation | 1 | NestJS scaffold, Prisma, RLS, Auth, Railway, CI/CD |
| 2. Twilio + Data | 2-3 | Contacts, webhooks, SMS send/receive, phone provisioning |
| 3. Inbox | 4-5 | Conversations, messages, WebSocket, frontend integration |
| 4. Cadence | 6-7 | Follow-up state machine, dispositions, scheduling |
| 5. Calling | 8-9 | WebRTC click-to-call, recording, lead alerts |
| 6. Hardening | 10-12 | Tests, load test, production deploy, first pilot clinic |
| 7. v1.5 | Post-v1 | Rebilling, Meta Ads, bulk SMS, AI follow-up |
| 8. v2 | Post-v1.5 | Social channels (IG, Messenger, WhatsApp, webchat, email) |

Full plan: [plans/260412-0034-contact-center-implementation/plan.md](plans/260412-0034-contact-center-implementation/plan.md)

## Security

- Multi-tenant isolation enforced at DB layer (RLS) AND app layer (TenantGuard)
- Twilio HMAC signature verification on all webhooks
- Idempotency keys on all webhook handlers
- No PII in logs or analytics events
- Secrets via environment variables only (never committed)
- Rate limiting via @nestjs/throttler with Redis store

## License

Proprietary. All rights reserved.
