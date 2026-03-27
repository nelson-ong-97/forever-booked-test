/**
 * ForeverBooked — Meta Marketing API proof-of-concept entry script.
 *
 * Launches a full campaign for a medical-spa offer:
 *   Campaign → Ad Set → (Ad Creative + Ad) × N angles
 *
 * All resources are created with status=PAUSED.
 * Run: npx ts-node src/create-campaign.ts
 */

import * as dotenv from "dotenv";
import path from "path";

dotenv.config({ path: path.resolve(__dirname, "../.env") });

import {
  createCampaign,
  createAdSet,
  createAdCreative,
  createAd,
  getCredentials,
} from "./meta-api-client";
import {
  OfferInput,
  CampaignInput,
  CampaignConfigInput,
  MetaCampaignResult,
} from "./types";
import { formatCentsToUsd } from "./helpers";

// ─── Sample data ──────────────────────────────────────────────────────────────

const offer: OfferInput = {
  name: "Spring Botox Special",
  price: 19900, // $199.00 in cents
  includedItems: [
    "20 units Botox",
    "Free consultation",
    "30-day follow-up included",
  ],
};

const campaign: CampaignInput = {
  name: "Spring 2026 Botox Campaign",
  objective: "OUTCOME_AWARENESS",
  angles: [
    {
      angleType: "SOCIAL_PROOF",
      angleName: "Social Proof",
      headline: "Join 500+ Happy Clients",
      primaryText:
        "Our clients love their results — and you will too. " +
        "ForeverBooked has helped hundreds of people look and feel their best " +
        "with our Spring Botox Special.",
      description: "See why clients keep coming back.",
      ctaType: "LEARN_MORE",
    },
    {
      angleType: "PAIN_POINT",
      angleName: "Pain Point",
      headline: "Tired of Fine Lines?",
      primaryText:
        "Don't let wrinkles hold you back. Our Spring Botox Special " +
        "delivers natural-looking results in under 30 minutes — " +
        "no downtime, no guesswork.",
      description: "Quick, proven, affordable.",
      ctaType: "SIGN_UP",
    },
    {
      angleType: "URGENCY_SCARCITY",
      angleName: "Urgency/Scarcity",
      headline: "Limited: Spring Special Ending Soon",
      primaryText:
        "Only 10 spots left at our Spring Botox price. " +
        "Once they're gone, the regular rate returns. " +
        "Book your appointment before it's too late.",
      description: "Offer expires end of March 2026.",
      ctaType: "BOOK_TRAVEL",
    },
  ],
};

const config: CampaignConfigInput = {
  dailyBudget: 30000, // đ30,000/day (~$1.20 USD) — VND ad account minimum is đ26,445
  targeting: {
    age_min: 25,
    age_max: 55,
    geo_locations: {
      countries: ["US"],
    },
  },
  placements: ["facebook_feed", "instagram_feed"],
};

// ─── Main execution ───────────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log("=== ForeverBooked — Meta Campaign Launcher ===");
  console.log(`Offer:    ${offer.name} (${formatCentsToUsd(offer.price)})`);
  console.log(`Campaign: ${campaign.name}`);
  console.log(`Angles:   ${campaign.angles.length}`);
  console.log("");

  // Step 1 — Create the campaign
  // If this fails we abort entirely — no point continuing without a campaign ID
  console.log("Step 1: Creating campaign...");
  let metaCampaignId: string;
  try {
    const campaignResult = await createCampaign(campaign.name, campaign.objective);
    metaCampaignId = campaignResult.id;
    console.log(`  Campaign ID: ${metaCampaignId}\n`);
  } catch (err) {
    console.error("FATAL: Campaign creation failed. Aborting.");
    console.error((err as Error).message);
    process.exit(1);
  }

  // Step 2 — Create the ad set
  // Also fatal — without an ad set we can't attach ads
  console.log("Step 2: Creating ad set...");
  let metaAdSetId: string;
  try {
    const adSetResult = await createAdSet(metaCampaignId, config);
    metaAdSetId = adSetResult.id;
    console.log(`  Ad Set ID: ${metaAdSetId}\n`);
  } catch (err) {
    console.error("FATAL: Ad set creation failed. Aborting.");
    console.error((err as Error).message);
    console.error(`  Partial state — Campaign ID: ${metaCampaignId}`);
    process.exit(1);
  }

  // Step 3 — Create creatives + ads per angle
  // Non-fatal per angle: log failures and continue to next angle
  console.log("Step 3: Creating ad creatives and ads...");
  const { pageId } = getCredentials();
  const adsResult: MetaCampaignResult["ads"] = [];

  for (const angle of campaign.angles) {
    console.log(`\n  Angle: ${angle.angleName} (${angle.angleType})`);
    let creativeId: string;

    try {
      const creative = await createAdCreative(angle, pageId);
      creativeId = creative.id;
    } catch (err) {
      console.error(
        `  ERROR: Creative creation failed for angle "${angle.angleName}" — skipping.`
      );
      console.error(`  ${(err as Error).message}`);
      continue;
    }

    let adId: string;
    try {
      const ad = await createAd(
        metaAdSetId,
        creativeId,
        `${campaign.name} — ${angle.angleName}`
      );
      adId = ad.id;
    } catch (err) {
      console.error(
        `  ERROR: Ad creation failed for angle "${angle.angleName}" — skipping.`
      );
      console.error(`  ${(err as Error).message}`);
      console.error(`  Partial state — Creative ID: ${creativeId}`);
      continue;
    }

    adsResult.push({
      metaAdId: adId,
      metaCreativeId: creativeId,
      angleName: angle.angleName,
    });
  }

  // ─── Summary table ──────────────────────────────────────────────────────────

  console.log("\n");
  console.log("=== Campaign Launch Summary ===");
  console.log(`Offer: ${offer.name} (${formatCentsToUsd(offer.price)})`);
  console.log(`Meta Campaign ID: ${metaCampaignId}`);
  console.log(`Meta Ad Set ID:   ${metaAdSetId}`);
  console.log("Ads:");

  if (adsResult.length === 0) {
    console.log("  (no ads were created successfully)");
  } else {
    for (const ad of adsResult) {
      console.log(
        `  - ${ad.angleName} → Ad ID: ${ad.metaAdId}, Creative ID: ${ad.metaCreativeId}`
      );
    }
  }

  const skipped = campaign.angles.length - adsResult.length;
  if (skipped > 0) {
    console.log(
      `\nNote: ${skipped} angle(s) failed — check errors above for details.`
    );
  }

  console.log("\nAll resources created with status=PAUSED.");
  console.log("Review in Meta Ads Manager before activating.");
}

main().catch((err: Error) => {
  console.error("Unhandled error:", err.message);
  process.exit(1);
});
