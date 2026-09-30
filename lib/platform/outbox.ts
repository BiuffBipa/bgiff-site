/**
 * Outbox: every e-mail is a row first, sent later by the drain cron. Nothing is sent to an entrant
 * unless flag `emails_enabled` is on; outside production only addresses on `email.send_allowlist`
 * receive anything (everything else is marked `suppressed` with a reason, visible in admin).
 */
export type EmailKind = "transactional" | "marketing";

export interface OutboxMessage {
  kind: EmailKind;
  toEmail: string;
  toSubmitterId?: string | null;
  templateKey: string;
  locale?: string;
  variables?: Record<string, unknown>;
  /** e.g. `film_ready:<film_id>` — a second enqueue with the same key is a no-op */
  idempotencyKey?: string;
  scheduledFor?: Date;
}

export interface OutboxRow extends OutboxMessage {
  status: "queued" | "suppressed";
  suppressedReason?: string;
}

export interface SendPolicyInput {
  environment: "production" | "staging" | "development" | "test";
  emailsEnabled: boolean;
  marketingEnabled: boolean;
  allowlist: readonly string[];
  suppressed: boolean;          // recipient is on the suppressions table
  marketingConsentConfirmed: boolean; // double opt-in confirmed (marketing only)
}

export type SendDecision = { send: true } | { send: false; reason: string };

/** Decides whether a queued message may leave the system at drain time. */
export function decideSend(msg: OutboxMessage, p: SendPolicyInput): SendDecision {
  if (p.suppressed) return { send: false, reason: "recipient_suppressed" };
  if (!p.emailsEnabled) return { send: false, reason: "flag_emails_enabled_off" };
  if (msg.kind === "marketing") {
    if (!p.marketingEnabled) return { send: false, reason: "flag_marketing_enabled_off" };
    if (!p.marketingConsentConfirmed) return { send: false, reason: "no_confirmed_marketing_consent" };
  }
  if (p.environment !== "production") {
    const to = msg.toEmail.trim().toLowerCase();
    if (!p.allowlist.map((a) => a.toLowerCase()).includes(to)) return { send: false, reason: "not_on_send_allowlist" };
  }
  return { send: true };
}

export interface OutboxStore {
  insert(row: OutboxRow): Promise<{ id: string; inserted: boolean }>;
}

export async function enqueue(store: OutboxStore, msg: OutboxMessage): Promise<{ id: string; inserted: boolean }> {
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(msg.toEmail)) throw new Error(`invalid recipient ${msg.toEmail}`);
  if (!msg.templateKey) throw new Error("templateKey required");
  return store.insert({ ...msg, locale: msg.locale ?? "en", variables: msg.variables ?? {}, status: "queued" });
}

/** Exponential back-off for failed sends: 1, 2, 4, 8 … minutes, capped at 6 h. */
export function nextAttemptAt(attempts: number, now: Date): Date {
  const minutes = Math.min(2 ** Math.max(attempts - 1, 0), 360);
  return new Date(now.getTime() + minutes * 60_000);
}
