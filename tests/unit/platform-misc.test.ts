import { describe, expect, it } from "vitest";
import { buildMagicLinkUrl, hashPii, issueToken, verifyToken } from "@/lib/platform/auth/magic-link";
import { decideSend, enqueue, nextAttemptAt, type OutboxRow } from "@/lib/platform/outbox";
import { memorySettings, parseSetting, readSettings, SettingsError } from "@/lib/platform/settings/registry";
import { Flags } from "@/lib/platform/settings/flags";
import { checkFit, eligibleAdditionalCategories, type CategoryRow } from "@/lib/platform/categories";

describe("magic links", () => {
  const now = new Date("2026-10-01T10:00:00Z");
  it("issues single-use, expiring tokens and never stores the raw token", () => {
    const t = issueToken(now, 15);
    expect(t.token).toHaveLength(43);
    expect(t.expiresAt.toISOString()).toBe("2026-10-01T10:15:00.000Z");
    const stored = { tokenHash: t.tokenHash, expiresAt: t.expiresAt, usedAt: null };
    expect(verifyToken(t.token, stored, now)).toEqual({ ok: true });
    expect(verifyToken(t.token, stored, new Date("2026-10-01T10:15:00Z"))).toEqual({ ok: false, reason: "expired" });
    expect(verifyToken(t.token, { ...stored, usedAt: now }, now)).toEqual({ ok: false, reason: "used" });
    expect(verifyToken("wrong", stored, now)).toEqual({ ok: false, reason: "mismatch" });
    expect(verifyToken(t.token, null, now)).toEqual({ ok: false, reason: "not_found" });
    expect(() => issueToken(now, 0)).toThrow(RangeError);
    expect(buildMagicLinkUrl("https://bgiff.com", "abc", "/my/films")).toBe("https://bgiff.com/auth/magic?t=abc&next=%2Fmy%2Ffilms");
  });
  it("hashes PII with a pepper", () => {
    expect(hashPii(" Voter@Example.com ", "pepper").equals(hashPii("voter@example.com", "pepper"))).toBe(true);
    expect(() => hashPii("x", "")).toThrow();
  });
});

describe("outbox policy", () => {
  const base = { environment: "staging" as const, emailsEnabled: true, marketingEnabled: true, allowlist: ["qa@bgiff.com"], suppressed: false, marketingConsentConfirmed: true };
  const msg = { kind: "transactional" as const, toEmail: "qa@bgiff.com", templateKey: "film_ready" };
  it("fails closed", () => {
    expect(decideSend(msg, base)).toEqual({ send: true });
    expect(decideSend(msg, { ...base, emailsEnabled: false })).toMatchObject({ send: false, reason: "flag_emails_enabled_off" });
    expect(decideSend({ ...msg, toEmail: "entrant@example.com" }, base)).toMatchObject({ send: false, reason: "not_on_send_allowlist" });
    expect(decideSend({ ...msg, toEmail: "entrant@example.com" }, { ...base, environment: "production" })).toEqual({ send: true });
    expect(decideSend(msg, { ...base, suppressed: true })).toMatchObject({ send: false, reason: "recipient_suppressed" });
    expect(decideSend({ ...msg, kind: "marketing" }, { ...base, marketingConsentConfirmed: false })).toMatchObject({ send: false, reason: "no_confirmed_marketing_consent" });
  });
  it("enqueues rows and backs off", async () => {
    const rows: OutboxRow[] = [];
    const store = { insert: async (r: OutboxRow) => { rows.push(r); return { id: String(rows.length), inserted: true }; } };
    await enqueue(store, msg);
    expect(rows[0]).toMatchObject({ status: "queued", locale: "en", variables: {} });
    await expect(enqueue(store, { ...msg, toEmail: "nope" })).rejects.toThrow();
    const now = new Date(0);
    expect(nextAttemptAt(1, now).getTime()).toBe(60_000);
    expect(nextAttemptAt(4, now).getTime()).toBe(8 * 60_000);
    expect(nextAttemptAt(20, now).getTime()).toBe(360 * 60_000);
  });
});

describe("settings & flags", () => {
  it("validates and refuses missing keys (no silent constants)", async () => {
    const src = memorySettings({ "gates.count": 5, "legal.vat_rate_bp": 1900 });
    expect(await readSettings(src, ["gates.count", "legal.vat_rate_bp"])).toEqual({ "gates.count": 5, "legal.vat_rate_bp": 1900 });
    await expect(readSettings(src, ["gates.jury_pool_min"])).rejects.toThrow(SettingsError);
    expect(() => parseSetting("legal.vat_rate_bp", 50000)).toThrow(SettingsError);
  });
  it("flags fail closed", () => {
    const f = Flags.fromRecord({ gates_public: true });
    expect(f.isOn("gates_public")).toBe(true);
    expect(f.isOn("payments_live")).toBe(false);
    expect(() => f.require("emails_enabled")).toThrow();
  });
});

describe("[C-1] category fit", () => {
  const cats: CategoryRow[] = [
    { key: "narrative_feature", name: "Narrative Feature", work_kind: "film", online_screening: true, active: true, fit_rules: { work_kind: "film", min_runtime_seconds: 2400 } },
    { key: "narrative_short", name: "Narrative Short", work_kind: "film", online_screening: true, active: true, fit_rules: { work_kind: "film", max_runtime_seconds: 2399 } },
    { key: "student", name: "Student", work_kind: "film", online_screening: true, active: true, fit_rules: { work_kind: "film", requires: ["is_student"] } },
    { key: "short_screenplay", name: "Short Screenplay", work_kind: "screenplay", online_screening: false, active: true, fit_rules: { work_kind: "screenplay" } },
    { key: "retired", name: "Retired", work_kind: "film", online_screening: true, active: false, fit_rules: {} },
  ];
  it("offers only fitting, active, not-yet-entered categories", () => {
    const short = { work_kind: "film" as const, runtime_seconds: 870, is_student: true };
    expect(eligibleAdditionalCategories(cats, short, ["narrative_short"]).map((f) => f.category.key)).toEqual(["student"]);
    expect(checkFit(cats[0], short).reasons).toEqual(["runtime_too_short"]);
    expect(checkFit(cats[3], short).reasons).toEqual(["work_kind_screenplay_required"]);
    expect(checkFit(cats[1], { work_kind: "film", runtime_seconds: null }).reasons).toEqual(["runtime_unknown"]);
    expect(checkFit(cats[2], { work_kind: "film", runtime_seconds: 100 }).reasons).toEqual(["requires_is_student"]);
  });
});
