/**
 * Application-wide constants.
 * Centralizes magic values for maintainability.
 */

// Meta Marketing API base URL — v25.0 (latest stable as of 2026)
export const META_API_BASE = "https://graph.facebook.com/v25.0";

// Meta API version string for reference in logs and docs
export const META_API_VERSION = "v25.0";

// Default campaign status on creation — PAUSED prevents accidental ad spend
export const DEFAULT_CAMPAIGN_STATUS = "PAUSED";

// Placeholder landing page URL — replace with real clinic booking page in production
export const PLACEHOLDER_LANDING_URL = "https://foreverbooked.com";

// Required environment variable names
export const ENV_KEYS = {
  META_ACCESS_TOKEN: "META_ACCESS_TOKEN",
  META_AD_ACCOUNT_ID: "META_AD_ACCOUNT_ID",
  META_PAGE_ID: "META_PAGE_ID",
} as const;
