/**
 * Domain types for ForeverBooked Meta Marketing API integration.
 * Mirrors the Prisma schema domain model used by the platform.
 */

// ─── Offer ───────────────────────────────────────────────────────────────────

/** A medical-spa service offer to be promoted via ad campaign. */
export interface OfferInput {
  /** Human-readable offer name, e.g. "Spring Botox Special" */
  name: string;
  /** Price in cents, e.g. 19900 = $199.00 */
  price: number;
  /** Line-items included in the offer, e.g. ["20 units Botox", "Free consultation"] */
  includedItems: string[];
}

// ─── Ad Angle ────────────────────────────────────────────────────────────────

/**
 * A single creative angle for an ad.
 * Each angle maps to one Meta AdCreative + Ad.
 */
export interface AdAngleInput {
  /** Category of angle, e.g. "SOCIAL_PROOF", "PAIN_POINT", "URGENCY_SCARCITY" */
  angleType: string;
  /** Short label used in reporting, e.g. "Social Proof" */
  angleName: string;
  /** Ad headline (up to ~40 chars for best display) */
  headline: string;
  /** Primary body text shown above the image */
  primaryText: string;
  /** Short description shown below the headline */
  description: string;
  /** Meta CTA button type, e.g. "LEARN_MORE", "BOOK_TRAVEL", "SIGN_UP" */
  ctaType: string;
  /** Optional image URL; if omitted the creative uses a link-only preview */
  imageUrl?: string;
}

// ─── Campaign ────────────────────────────────────────────────────────────────

/** Top-level campaign definition. */
export interface CampaignInput {
  /** Campaign display name in Meta Ads Manager */
  name: string;
  /** Meta objective, e.g. "OUTCOME_AWARENESS", "OUTCOME_LEADS" */
  objective: string;
  /** One or more creative angles to launch as separate ads within the campaign */
  angles: AdAngleInput[];
}

// ─── Campaign Config ─────────────────────────────────────────────────────────

/** Delivery and targeting configuration for the ad set. */
export interface CampaignConfigInput {
  /** Daily spend cap in cents, e.g. 1000 = $10.00/day */
  dailyBudget: number;
  /** Meta targeting spec */
  targeting: {
    age_min: number;
    age_max: number;
    /** Geo-locations spec — see Meta Marketing API targeting_spec docs */
    geo_locations: {
      countries?: string[];
      cities?: Array<{ key: string; radius: number; distance_unit: string }>;
      regions?: Array<{ key: string }>;
    };
  };
  /** Meta placement strings, e.g. ["facebook_feed", "instagram_feed"] */
  placements: string[];
}

// ─── Results ─────────────────────────────────────────────────────────────────

/** IDs returned after a successful campaign launch. */
export interface MetaCampaignResult {
  metaCampaignId: string;
  metaAdSetId: string;
  ads: Array<{
    metaAdId: string;
    metaCreativeId: string;
    angleName: string;
  }>;
}

// ─── Error ───────────────────────────────────────────────────────────────────

/** Shape of an error object returned by the Meta Graph API. */
export interface MetaApiError {
  message: string;
  type: string;
  code: number;
  error_subcode?: number;
  fbtrace_id?: string;
}
