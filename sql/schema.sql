-- ForeverBooked Campaign Launcher Schema
-- PostgreSQL DDL — generated from Prisma schema with annotations
-- All monetary values in cents (integer). Timestamps in UTC.

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE "CampaignStatus" AS ENUM (
  'DRAFT', 'PENDING_LAUNCH', 'LAUNCHING', 'ACTIVE',
  'PAUSED', 'COMPLETED', 'FAILED', 'CANCELLED'
);

CREATE TYPE "CampaignObjective" AS ENUM (
  'AWARENESS', 'TRAFFIC', 'ENGAGEMENT', 'LEADS', 'SALES'
);

CREATE TYPE "AdAngleType" AS ENUM (
  'HOLIDAY_SEASONAL', 'PAIN_POINT', 'SOCIAL_PROOF',
  'URGENCY_SCARCITY', 'BEFORE_AFTER', 'EDUCATIONAL'
);

CREATE TYPE "MediaType" AS ENUM ('IMAGE', 'VIDEO');
CREATE TYPE "BudgetType" AS ENUM ('DAILY', 'LIFETIME');
CREATE TYPE "UserRole" AS ENUM ('OWNER', 'ADMIN', 'MEMBER');
CREATE TYPE "StatusChangeSource" AS ENUM ('USER', 'META_SYNC', 'SYSTEM');

-- ============================================================================
-- CORE TENANT TABLES
-- ============================================================================

-- Root tenant entity. Each clinic = isolated tenant.
CREATE TABLE clinics (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  location   TEXT NOT NULL,
  timezone   TEXT NOT NULL DEFAULT 'America/New_York',
  brand_voice   JSONB,  -- Freeform brand descriptors for AI copy generation
  trust_signals JSONB,  -- Certifications, years in business, etc.
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- Users belong to one clinic. Role-based access.
CREATE TABLE users (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(id),
  email     TEXT NOT NULL UNIQUE,
  name      TEXT NOT NULL,
  role      "UserRole" NOT NULL DEFAULT 'MEMBER',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
CREATE INDEX idx_users_clinic_id ON users(clinic_id);

-- Per-clinic Meta OAuth connection. 1:1 with clinic.
-- Tokens encrypted at application level before storage.
CREATE TABLE meta_oauth_tokens (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id        UUID NOT NULL UNIQUE REFERENCES clinics(id),
  ad_account_id    TEXT NOT NULL,          -- Meta's act_XXXXX format
  access_token     TEXT NOT NULL,          -- Encrypted at app level
  token_expires_at TIMESTAMPTZ NOT NULL,
  refresh_token    TEXT,                   -- Encrypted, may be null
  meta_page_id     TEXT,                   -- Facebook page for ad delivery
  scopes           TEXT[] NOT NULL,        -- Granted OAuth scopes
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- OFFER DOMAIN
-- ============================================================================

-- System-level templates. No clinic_id — shared across all tenants.
CREATE TABLE offer_templates (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  category      TEXT NOT NULL,
  default_price INT NOT NULL,              -- In cents
  default_items JSONB NOT NULL,            -- Array of included items
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Clinic-specific offers, optionally from a template.
CREATE TABLE offers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id       UUID NOT NULL REFERENCES clinics(id),
  template_id     UUID REFERENCES offer_templates(id),
  name            TEXT NOT NULL,
  price           INT NOT NULL,            -- In cents
  included_items  JSONB NOT NULL,
  scarcity_detail TEXT,                    -- e.g., "Only 10 spots available"
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);
CREATE INDEX idx_offers_clinic_id ON offers(clinic_id);

-- ============================================================================
-- CAMPAIGN DOMAIN
-- ============================================================================

-- Maps to Meta Campaign. clinic_id denormalized for direct tenant queries.
CREATE TABLE campaigns (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id        UUID NOT NULL REFERENCES clinics(id),
  offer_id         UUID NOT NULL REFERENCES offers(id),
  name             TEXT NOT NULL,
  objective        "CampaignObjective" NOT NULL,
  status           "CampaignStatus" NOT NULL DEFAULT 'DRAFT',
  meta_campaign_id TEXT,                   -- Populated after successful Meta launch
  launched_at      TIMESTAMPTZ,
  error_message    TEXT,
  idempotency_key  TEXT UNIQUE,            -- Prevents duplicate launches on retry
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at       TIMESTAMPTZ
);
CREATE INDEX idx_campaigns_clinic_status ON campaigns(clinic_id, status);
CREATE INDEX idx_campaigns_offer_id ON campaigns(offer_id);
CREATE INDEX idx_campaigns_meta_id ON campaigns(meta_campaign_id);

-- 1:1 with campaign. Maps to Meta Ad Set.
-- Separated to keep Campaign focused on lifecycle, Config on targeting/budget.
CREATE TABLE campaign_configs (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id        UUID NOT NULL UNIQUE REFERENCES campaigns(id) ON DELETE CASCADE,
  budget_type        "BudgetType" NOT NULL DEFAULT 'DAILY',
  budget_amount      INT NOT NULL,         -- In cents
  audience_targeting JSONB NOT NULL,       -- Meta targeting spec (age, geo, interests)
  placements         JSONB NOT NULL,       -- e.g., ["facebook_feed", "instagram_stories"]
  schedule_start     TIMESTAMPTZ NOT NULL,
  schedule_end       TIMESTAMPTZ,          -- Null = runs until stopped/exhausted
  meta_ad_set_id     TEXT,                 -- Populated after Meta launch
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Each ad = one angle's creative. Maps to Meta Ad + Ad Creative.
CREATE TABLE ads (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id     UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  angle_type      "AdAngleType" NOT NULL,
  angle_name      TEXT NOT NULL,
  headline        TEXT,
  primary_text    TEXT,
  description     TEXT,
  cta_type        TEXT,                    -- e.g., "LEARN_MORE", "BOOK_NOW"
  meta_ad_id      TEXT,
  meta_creative_id TEXT,
  status          "CampaignStatus" NOT NULL DEFAULT 'DRAFT',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);
CREATE INDEX idx_ads_campaign_id ON ads(campaign_id);

-- Media attachments per ad. Supports multiple (carousel, variants).
CREATE TABLE ad_media (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ad_id           UUID NOT NULL REFERENCES ads(id) ON DELETE CASCADE,
  media_type      "MediaType" NOT NULL,
  media_url       TEXT NOT NULL,
  file_name       TEXT,
  sort_order      INT NOT NULL DEFAULT 0,
  meta_image_hash TEXT,                    -- Avoids re-uploading same image to Meta
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ad_media_ad_id ON ad_media(ad_id);

-- ============================================================================
-- AUDIT & SYNC TABLES
-- ============================================================================

-- Append-only status change log. Never updated or deleted.
-- Enables full campaign history reconstruction.
CREATE TABLE campaign_status_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id     UUID NOT NULL REFERENCES campaigns(id),
  previous_status "CampaignStatus" NOT NULL,
  new_status      "CampaignStatus" NOT NULL,
  source          "StatusChangeSource" NOT NULL,
  changed_by      UUID REFERENCES users(id),  -- User ID if source=USER
  note            TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_status_log_campaign ON campaign_status_log(campaign_id, created_at);

-- Raw Meta API sync events. Stores full responses for debugging.
CREATE TABLE meta_sync_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id  UUID NOT NULL REFERENCES campaigns(id),
  sync_type    TEXT NOT NULL,              -- e.g., "performance_fetch", "campaign_create"
  raw_response JSONB NOT NULL,
  success      BOOLEAN NOT NULL DEFAULT true,
  error_code   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sync_log_campaign ON meta_sync_log(campaign_id, created_at);
CREATE INDEX idx_sync_log_type ON meta_sync_log(sync_type);
