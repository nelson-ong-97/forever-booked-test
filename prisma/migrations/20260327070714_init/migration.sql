-- CreateEnum
CREATE TYPE "StatusChangeSource" AS ENUM ('USER', 'META_SYNC', 'SYSTEM');

-- CreateEnum
CREATE TYPE "CampaignStatus" AS ENUM ('DRAFT', 'PENDING_LAUNCH', 'LAUNCHING', 'ACTIVE', 'PAUSED', 'COMPLETED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "CampaignObjective" AS ENUM ('AWARENESS', 'TRAFFIC', 'ENGAGEMENT', 'LEADS', 'SALES');

-- CreateEnum
CREATE TYPE "AdAngleType" AS ENUM ('HOLIDAY_SEASONAL', 'PAIN_POINT', 'SOCIAL_PROOF', 'URGENCY_SCARCITY', 'BEFORE_AFTER', 'EDUCATIONAL');

-- CreateEnum
CREATE TYPE "MediaType" AS ENUM ('IMAGE', 'VIDEO');

-- CreateEnum
CREATE TYPE "BudgetType" AS ENUM ('DAILY', 'LIFETIME');

-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('OWNER', 'ADMIN', 'MEMBER');

-- CreateTable
CREATE TABLE "campaign_status_log" (
    "id" TEXT NOT NULL,
    "campaign_id" TEXT NOT NULL,
    "previous_status" "CampaignStatus" NOT NULL,
    "new_status" "CampaignStatus" NOT NULL,
    "source" "StatusChangeSource" NOT NULL,
    "changed_by" TEXT,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "campaign_status_log_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "meta_sync_log" (
    "id" TEXT NOT NULL,
    "campaign_id" TEXT NOT NULL,
    "syncType" TEXT NOT NULL,
    "raw_response" JSONB NOT NULL,
    "success" BOOLEAN NOT NULL DEFAULT true,
    "error_code" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "meta_sync_log_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "campaigns" (
    "id" TEXT NOT NULL,
    "clinic_id" TEXT NOT NULL,
    "offer_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "objective" "CampaignObjective" NOT NULL,
    "status" "CampaignStatus" NOT NULL DEFAULT 'DRAFT',
    "meta_campaign_id" TEXT,
    "launched_at" TIMESTAMP(3),
    "error_message" TEXT,
    "idempotency_key" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "campaign_configs" (
    "id" TEXT NOT NULL,
    "campaign_id" TEXT NOT NULL,
    "budget_type" "BudgetType" NOT NULL DEFAULT 'DAILY',
    "budget_amount" INTEGER NOT NULL,
    "audience_targeting" JSONB NOT NULL,
    "placements" JSONB NOT NULL,
    "schedule_start" TIMESTAMP(3) NOT NULL,
    "schedule_end" TIMESTAMP(3),
    "meta_ad_set_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "campaign_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ads" (
    "id" TEXT NOT NULL,
    "campaign_id" TEXT NOT NULL,
    "angle_type" "AdAngleType" NOT NULL,
    "angle_name" TEXT NOT NULL,
    "headline" TEXT,
    "primary_text" TEXT,
    "description" TEXT,
    "cta_type" TEXT,
    "meta_ad_id" TEXT,
    "meta_creative_id" TEXT,
    "status" "CampaignStatus" NOT NULL DEFAULT 'DRAFT',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "ads_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ad_media" (
    "id" TEXT NOT NULL,
    "ad_id" TEXT NOT NULL,
    "media_type" "MediaType" NOT NULL,
    "media_url" TEXT NOT NULL,
    "file_name" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "meta_image_hash" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ad_media_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "clinics" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "location" TEXT NOT NULL,
    "timezone" TEXT NOT NULL DEFAULT 'America/New_York',
    "brandVoice" JSONB,
    "trustSignals" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "clinics_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "clinic_id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "role" "UserRole" NOT NULL DEFAULT 'MEMBER',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "meta_oauth_tokens" (
    "id" TEXT NOT NULL,
    "clinic_id" TEXT NOT NULL,
    "ad_account_id" TEXT NOT NULL,
    "access_token" TEXT NOT NULL,
    "token_expires_at" TIMESTAMP(3) NOT NULL,
    "refresh_token" TEXT,
    "meta_page_id" TEXT,
    "scopes" TEXT[],
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "meta_oauth_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "offer_templates" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "defaultPrice" INTEGER NOT NULL,
    "defaultItems" JSONB NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "offer_templates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "offers" (
    "id" TEXT NOT NULL,
    "clinic_id" TEXT NOT NULL,
    "template_id" TEXT,
    "name" TEXT NOT NULL,
    "price" INTEGER NOT NULL,
    "includedItems" JSONB NOT NULL,
    "scarcity_detail" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "offers_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "campaign_status_log_campaign_id_created_at_idx" ON "campaign_status_log"("campaign_id", "created_at");

-- CreateIndex
CREATE INDEX "meta_sync_log_campaign_id_created_at_idx" ON "meta_sync_log"("campaign_id", "created_at");

-- CreateIndex
CREATE INDEX "meta_sync_log_syncType_idx" ON "meta_sync_log"("syncType");

-- CreateIndex
CREATE UNIQUE INDEX "campaigns_idempotency_key_key" ON "campaigns"("idempotency_key");

-- CreateIndex
CREATE INDEX "campaigns_clinic_id_status_idx" ON "campaigns"("clinic_id", "status");

-- CreateIndex
CREATE INDEX "campaigns_offer_id_idx" ON "campaigns"("offer_id");

-- CreateIndex
CREATE INDEX "campaigns_meta_campaign_id_idx" ON "campaigns"("meta_campaign_id");

-- CreateIndex
CREATE UNIQUE INDEX "campaign_configs_campaign_id_key" ON "campaign_configs"("campaign_id");

-- CreateIndex
CREATE INDEX "ads_campaign_id_idx" ON "ads"("campaign_id");

-- CreateIndex
CREATE INDEX "ad_media_ad_id_idx" ON "ad_media"("ad_id");

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "users_clinic_id_idx" ON "users"("clinic_id");

-- CreateIndex
CREATE UNIQUE INDEX "meta_oauth_tokens_clinic_id_key" ON "meta_oauth_tokens"("clinic_id");

-- CreateIndex
CREATE INDEX "offers_clinic_id_idx" ON "offers"("clinic_id");

-- AddForeignKey
ALTER TABLE "campaign_status_log" ADD CONSTRAINT "campaign_status_log_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "campaigns"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "campaign_status_log" ADD CONSTRAINT "campaign_status_log_changed_by_fkey" FOREIGN KEY ("changed_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meta_sync_log" ADD CONSTRAINT "meta_sync_log_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "campaigns"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "campaigns" ADD CONSTRAINT "campaigns_clinic_id_fkey" FOREIGN KEY ("clinic_id") REFERENCES "clinics"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "campaigns" ADD CONSTRAINT "campaigns_offer_id_fkey" FOREIGN KEY ("offer_id") REFERENCES "offers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "campaign_configs" ADD CONSTRAINT "campaign_configs_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "campaigns"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ads" ADD CONSTRAINT "ads_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "campaigns"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ad_media" ADD CONSTRAINT "ad_media_ad_id_fkey" FOREIGN KEY ("ad_id") REFERENCES "ads"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_clinic_id_fkey" FOREIGN KEY ("clinic_id") REFERENCES "clinics"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "meta_oauth_tokens" ADD CONSTRAINT "meta_oauth_tokens_clinic_id_fkey" FOREIGN KEY ("clinic_id") REFERENCES "clinics"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "offers" ADD CONSTRAINT "offers_clinic_id_fkey" FOREIGN KEY ("clinic_id") REFERENCES "clinics"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "offers" ADD CONSTRAINT "offers_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "offer_templates"("id") ON DELETE SET NULL ON UPDATE CASCADE;
