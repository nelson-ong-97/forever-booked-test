/**
 * Meta Marketing API v25.0 — resource creation functions.
 * Uses native fetch (Node 18+) via meta-http-post.ts — no Meta SDK.
 * All resources created with status=PAUSED to prevent accidental spend.
 */

import { CampaignConfigInput, AdAngleInput } from "./types";
import { metaPost, getCredentials } from "./meta-http-post";
import { DEFAULT_CAMPAIGN_STATUS, PLACEHOLDER_LANDING_URL } from "./constants";
import { formatCentsToUsd } from "./helpers";

export { getCredentials };

// ─── Campaign ─────────────────────────────────────────────────────────────────

/**
 * Create a top-level campaign under the ad account.
 * special_ad_categories is required by Meta even when empty — omitting causes rejection.
 */
export async function createCampaign(
  name: string,
  objective: string
): Promise<{ id: string }> {
  const { adAccountId } = getCredentials();

  console.log(`  [Meta] Creating campaign: "${name}" (objective: ${objective})`);

  const result = await metaPost<{ id: string }>(`/${adAccountId}/campaigns`, {
    name,
    objective,
    status: DEFAULT_CAMPAIGN_STATUS,
    special_ad_categories: [], // required field — omitting causes API rejection
    is_adset_budget_sharing_enabled: false, // required in v25.0 when not using campaign budget
  });

  console.log(`  [Meta] Campaign created → ID: ${result.id}`);
  return result;
}

// ─── Ad Set ───────────────────────────────────────────────────────────────────

/**
 * Create an ad set inside a campaign.
 * Translates CampaignConfigInput placements into Meta publisher_platforms format.
 */
export async function createAdSet(
  campaignId: string,
  config: CampaignConfigInput
): Promise<{ id: string }> {
  const { adAccountId } = getCredentials();

  // Build targeting spec — map placement strings to Meta's positional fields
  const targeting: Record<string, unknown> = {
    age_min: config.targeting.age_min,
    age_max: config.targeting.age_max,
    geo_locations: config.targeting.geo_locations,
    targeting_automation: { advantage_audience: 0 }, // v25.0: explicit opt-out of Advantage audience
  };

  if (config.placements.length > 0) {
    const publisherPlatforms = new Set<string>();
    const facebookPositions: string[] = [];
    const instagramPositions: string[] = [];

    // Map placement strings to Meta's publisher_platforms and position fields.
    // v25.0 renamed Instagram "feed" position to "stream".
    const igPositionMap: Record<string, string> = { feed: "stream" };

    for (const placement of config.placements) {
      if (placement.startsWith("facebook_")) {
        publisherPlatforms.add("facebook");
        facebookPositions.push(placement.replace("facebook_", ""));
      } else if (placement.startsWith("instagram_")) {
        publisherPlatforms.add("instagram");
        const raw = placement.replace("instagram_", "");
        instagramPositions.push(igPositionMap[raw] ?? raw);
      }
    }

    targeting.publisher_platforms = Array.from(publisherPlatforms);
    if (facebookPositions.length > 0) targeting.facebook_positions = facebookPositions;
    if (instagramPositions.length > 0) targeting.instagram_positions = instagramPositions;
  }

  console.log(
    `  [Meta] Creating ad set for campaign ${campaignId} ` +
      `(budget: ${formatCentsToUsd(config.dailyBudget)}/day)`
  );

  const result = await metaPost<{ id: string }>(`/${adAccountId}/adsets`, {
    campaign_id: campaignId,
    name: `Ad Set — ${new Date().toISOString().slice(0, 10)}`,
    daily_budget: config.dailyBudget, // cents
    targeting,
    optimization_goal: "REACH",
    billing_event: "IMPRESSIONS",
    bid_strategy: "LOWEST_COST_WITHOUT_CAP", // v25.0 requires explicit bid strategy
    status: DEFAULT_CAMPAIGN_STATUS,
    start_time: Math.floor(Date.now() / 1000), // Unix timestamp required by Meta
  });

  console.log(`  [Meta] Ad set created → ID: ${result.id}`);
  return result;
}

// ─── Ad Creative ──────────────────────────────────────────────────────────────

/**
 * Create an ad creative from a single angle's copy.
 * Uses object_story_spec + link_data for standard link-preview ad format.
 */
export async function createAdCreative(
  adInput: AdAngleInput,
  pageId: string
): Promise<{ id: string }> {
  const { adAccountId } = getCredentials();

  console.log(`  [Meta] Creating creative for angle: "${adInput.angleName}"`);

  const linkData: Record<string, unknown> = {
    message: adInput.primaryText,
    link: PLACEHOLDER_LANDING_URL,
    name: adInput.headline,
    description: adInput.description,
    call_to_action: {
      type: adInput.ctaType,
      value: { link: PLACEHOLDER_LANDING_URL },
    },
  };

  if (adInput.imageUrl) {
    linkData.picture = adInput.imageUrl;
  }

  const result = await metaPost<{ id: string }>(`/${adAccountId}/adcreatives`, {
    name: `Creative — ${adInput.angleName}`,
    object_story_spec: {
      page_id: pageId,
      link_data: linkData,
    },
  });

  console.log(`  [Meta] Creative created → ID: ${result.id}`);
  return result;
}

// ─── Ad ───────────────────────────────────────────────────────────────────────

/**
 * Create an ad that pairs an ad set with a creative.
 * Activate manually in Meta Ads Manager after creative review.
 */
export async function createAd(
  adSetId: string,
  creativeId: string,
  name: string
): Promise<{ id: string }> {
  const { adAccountId } = getCredentials();

  console.log(`  [Meta] Creating ad: "${name}"`);

  const result = await metaPost<{ id: string }>(`/${adAccountId}/ads`, {
    adset_id: adSetId,
    name,
    creative: { creative_id: creativeId },
    status: DEFAULT_CAMPAIGN_STATUS,
  });

  console.log(`  [Meta] Ad created → ID: ${result.id}`);
  return result;
}
