/**
 * Shared utility/helper functions used across the application.
 */

/**
 * Validates that a required environment variable is set.
 * Throws a descriptive error if missing — fail fast at startup, not mid-request.
 */
export function requireEnv(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

/**
 * Formats a cent-based price for display.
 * e.g., 19900 → "$199.00"
 */
export function formatCentsToUsd(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}
