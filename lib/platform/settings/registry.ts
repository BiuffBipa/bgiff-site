/**
 * Typed registry of editable settings. The VALUES live in the `settings` table (seeded in
 * supabase/migrations/20260930001000_seed_defaults.sql) and are edited by admins; this file only
 * declares keys and their shape so the app can validate what it reads. There are intentionally no
 * numeric defaults here: a missing row is an error, not a silent fallback to a constant.
 */
import { z } from "zod";

export const SETTINGS = {
  "festival.name": z.string(),
  "festival.short_name": z.string(),
  "festival.edition": z.string(),
  "festival.event_date": z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  "festival.deadlines": z.array(z.object({ key: z.string(), label: z.string(), date: z.string() })),
  "festival.entry_target": z.number().int().positive(),
  "legal.operator": z.string(),
  "legal.owner": z.string(),
  "legal.address": z.object({ street: z.string(), postal_code: z.string(), city: z.string(), country: z.string() }),
  "legal.email": z.string().email(),
  "legal.ust_idnr": z.string().nullable(),
  "legal.vat_rate_bp": z.number().int().min(0).max(10_000),
  "legal.oss_threshold_cents": z.number().int().nonnegative(),
  "legal.invoice_prefix": z.string(),
  "legal.credit_note_prefix": z.string(),
  "legal.order_prefix": z.string(),
  "contact.routing": z.record(z.string(), z.string().email()),
  "intake.distributor_threshold": z.number().int().positive(),
  "intake.dedup_runtime_tolerance_seconds": z.number().int().nonnegative(),
  "intake.dedup_fuzzy_threshold": z.number().min(0).max(1),
  "intake.batch_size": z.number().int().positive(),
  "gates.count": z.number().int().positive(),
  "gates.jury_pool_min": z.number().int().positive(),
  "gates.jury_pool_max": z.number().int().positive(),
  "gates.default_booking_fee_cents": z.number().int().nonnegative(),
  "gates.checkout_rate_limit": z.object({ per_ip_per_10min: z.number().int(), per_email_per_10min: z.number().int() }),
  "gates.max_qty_per_checkout": z.number().int().positive(),
  "email.transactional_domain": z.string(),
  "email.marketing_domain": z.string(),
  "email.from_name": z.string(),
  "email.reply_to": z.string().email(),
  "email.send_allowlist": z.array(z.string().email()),
  "email.batch_size": z.number().int().positive(),
  "auth.magic_link_ttl_minutes": z.number().int().positive(),
  "auth.magic_link_rate_limit": z.object({ per_email_per_15min: z.number().int(), per_ip_per_15min: z.number().int() }),
  "media.max_upload_bytes": z.number().int().positive(),
  "media.playback_token_ttl_seconds": z.number().int().positive(),
  "ai.default_model": z.string(),
  "ai.cheap_model": z.string(),
  "ai.daily_digest_hour_utc": z.number().int().min(0).max(23),
  "brand.palette": z.record(z.string(), z.string()),
} as const;

export type SettingKey = keyof typeof SETTINGS;
export type SettingValue<K extends SettingKey> = z.infer<(typeof SETTINGS)[K]>;

/** Anything that can fetch raw JSON values by key (Supabase client, test map, cache). */
export interface SettingsSource {
  getMany(keys: readonly string[]): Promise<Record<string, unknown>>;
}

export class SettingsError extends Error {
  constructor(public readonly key: string, message: string) {
    super(`setting ${key}: ${message}`);
  }
}

export async function readSetting<K extends SettingKey>(source: SettingsSource, key: K): Promise<SettingValue<K>> {
  const raw = await source.getMany([key]);
  return parseSetting(key, raw[key]);
}

export async function readSettings<K extends SettingKey>(source: SettingsSource, keys: readonly K[]): Promise<{ [P in K]: SettingValue<P> }> {
  const raw = await source.getMany(keys);
  const out = {} as { [P in K]: SettingValue<P> };
  for (const key of keys) out[key] = parseSetting(key, raw[key]);
  return out;
}

export function parseSetting<K extends SettingKey>(key: K, value: unknown): SettingValue<K> {
  if (value === undefined) throw new SettingsError(key, "missing — seed or set it in the settings table");
  const result = SETTINGS[key].safeParse(value);
  if (!result.success) throw new SettingsError(key, result.error.issues.map((i) => i.message).join("; "));
  return result.data as SettingValue<K>;
}

/** In-memory source for tests and scripts. */
export function memorySettings(values: Partial<{ [K in SettingKey]: SettingValue<K> }>): SettingsSource {
  return { getMany: async (keys) => Object.fromEntries(keys.filter((k) => k in values).map((k) => [k, (values as Record<string, unknown>)[k]])) };
}
