/**
 * Magic links: no passwords, no sign-up. A token is 32 random bytes, shown once in a URL, and only
 * its SHA-256 is stored (magic_link_tokens.token_hash). Single use, TTL from settings
 * (auth.magic_link_ttl_minutes), bound to a hashed user-agent/IP for anomaly detection (not hard binding —
 * many entrants open links on another device).
 */
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

export interface IssuedToken {
  token: string;       // base64url, goes in the URL, never stored
  tokenHash: Buffer;   // stored
  expiresAt: Date;
}

export function issueToken(now: Date, ttlMinutes: number): IssuedToken {
  if (!Number.isInteger(ttlMinutes) || ttlMinutes <= 0 || ttlMinutes > 60 * 24) throw new RangeError("ttlMinutes out of range");
  const token = randomBytes(32).toString("base64url");
  return { token, tokenHash: hashToken(token), expiresAt: new Date(now.getTime() + ttlMinutes * 60_000) };
}

export function hashToken(token: string): Buffer {
  return createHash("sha256").update(token, "utf8").digest();
}

export function hashPii(value: string, pepper: string): Buffer {
  if (!pepper) throw new Error("PII hashing requires a pepper (HASH_PEPPER)");
  return createHash("sha256").update(pepper).update("\u0000").update(value.trim().toLowerCase()).digest();
}

export interface StoredToken {
  tokenHash: Buffer;
  expiresAt: Date;
  usedAt: Date | null;
}

export type Verify = { ok: true } | { ok: false; reason: "not_found" | "expired" | "used" | "mismatch" };

export function verifyToken(presented: string, stored: StoredToken | null, now: Date): Verify {
  if (!stored) return { ok: false, reason: "not_found" };
  const h = hashToken(presented);
  if (h.length !== stored.tokenHash.length || !timingSafeEqual(h, stored.tokenHash)) return { ok: false, reason: "mismatch" };
  if (stored.usedAt) return { ok: false, reason: "used" };
  if (now.getTime() >= stored.expiresAt.getTime()) return { ok: false, reason: "expired" };
  return { ok: true };
}

export function buildMagicLinkUrl(baseUrl: string, token: string, next = "/my"): string {
  const u = new URL("/auth/magic", baseUrl);
  u.searchParams.set("t", token);
  if (next.startsWith("/")) u.searchParams.set("next", next);
  return u.toString();
}
