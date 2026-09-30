/**
 * Feature flags. Every live switch (emails, payments, gates, public leaderboard…) is a row in
 * `feature_flags`, default OFF, flipped only by the founder. This module only names them.
 */
export const FLAGS = [
  "admin_enabled",
  "filmmaker_dashboard_enabled",
  "emails_enabled",
  "marketing_enabled",
  "online_screening_open",
  "payments_live",
  "gates_open",
  "gates_public",
  "faq_autoreply",
  "batch_approve_screening",
  "filmmaker_category_change_after_confirm",
  "intake_filmfreeway_api",
  "intake_webhooks",
  "locale_de",
] as const;
export type FlagKey = (typeof FLAGS)[number];

export interface FlagSource {
  getAll(): Promise<Partial<Record<FlagKey, boolean>>>;
}

export class Flags {
  private constructor(private readonly values: Partial<Record<FlagKey, boolean>>) {}
  static async load(source: FlagSource): Promise<Flags> {
    return new Flags(await source.getAll());
  }
  static fromRecord(values: Partial<Record<FlagKey, boolean>>): Flags {
    return new Flags(values);
  }
  /** Unknown or missing flag → false. Never throws: a missing switch must fail closed. */
  isOn(key: FlagKey): boolean {
    return this.values[key] === true;
  }
  /** Guard that throws a 404-style error for routes that must not exist while a flag is off. */
  require(key: FlagKey): void {
    if (!this.isOn(key)) {
      const err = new Error(`feature ${key} is off`);
      (err as Error & { status: number }).status = 404;
      throw err;
    }
  }
}
