/**
 * Low-level HTTP POST helper for the Meta Graph API.
 * Handles credential loading, form-encoding, and error parsing.
 * Used exclusively by meta-api-client.ts.
 */

import { MetaApiError } from "./types";
import { META_API_BASE, ENV_KEYS } from "./constants";
import { requireEnv } from "./helpers";

// ─── Credential helpers ───────────────────────────────────────────────────────

/** Returns validated Meta credentials from environment variables. */
export function getCredentials() {
  return {
    accessToken: requireEnv(ENV_KEYS.META_ACCESS_TOKEN, process.env.META_ACCESS_TOKEN),
    adAccountId: requireEnv(ENV_KEYS.META_AD_ACCOUNT_ID, process.env.META_AD_ACCOUNT_ID),
    pageId: requireEnv(ENV_KEYS.META_PAGE_ID, process.env.META_PAGE_ID),
  };
}

// ─── HTTP POST ────────────────────────────────────────────────────────────────

/**
 * POST form-encoded data to a Meta Graph API endpoint.
 * Objects/arrays are JSON-stringified per Meta's API contract.
 * Throws a descriptive error with Meta error details on API-level failures.
 */
export async function metaPost<T>(
  endpoint: string,
  params: Record<string, unknown>
): Promise<T> {
  const { accessToken } = getCredentials();

  const body = new URLSearchParams();
  body.append("access_token", accessToken);

  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    // Meta expects JSON-stringified objects/arrays in form-encoded bodies
    body.append(
      key,
      typeof value === "object" ? JSON.stringify(value) : String(value)
    );
  }

  const url = `${META_API_BASE}${endpoint}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  const json = (await response.json()) as { error?: MetaApiError } & T;

  if (!response.ok || json.error) {
    const err = json.error;
    // Log full error for debugging
    if (err) console.error("  [Meta] Full error response:", JSON.stringify(err, null, 2));
    throw new Error(
      `Meta API error on POST ${endpoint}: ` +
        (err
          ? `[${err.type} / code ${err.code}${err.error_subcode ? `/${err.error_subcode}` : ""}] ${err.message}`
          : `HTTP ${response.status}`)
    );
  }

  return json;
}
