/**
 * decideAccess() — the single application-side authorisation entrypoint.
 * It mirrors the RLS policies in supabase/migrations/20260930000900_rls.sql.
 * The app calls it BEFORE touching the database (with the service-role client for staff
 * actions); RLS remains the safety net for direct/PostgREST access. Keep both in sync:
 * every change here needs a policy change and an RLS test, and vice versa.
 */

export const ROLES = [
  "founder", "admin", "screener", "programmer", "juror", "support", "finance", "filmmaker", "distributor", "public",
] as const;
export type Role = (typeof ROLES)[number];

export type Action = "read" | "create" | "update" | "delete" | "decide" | "sign_off" | "flip_flag" | "export";

export type Resource =
  | "submitter" | "film" | "entry" | "film_asset" | "consent" | "film_note" | "tag"
  | "screening_flag" | "screening_assignment" | "screening_decision"
  | "juror" | "jury_assignment" | "score" | "conflict" | "result" | "honour"
  | "gate" | "gate_film" | "vote" | "laurel" | "fraud_alert"
  | "product" | "price" | "coupon" | "order" | "invoice" | "refund" | "entitlement"
  | "outbox" | "email_event" | "campaign" | "segment" | "automation" | "crm_activity" | "task"
  | "setting" | "feature_flag" | "decision" | "document" | "audit_log" | "agent_run" | "agent_proposal"
  | "site_page" | "faq" | "journal_post" | "programme_item" | "import_run" | "webhook_event" | "report";

export interface Actor {
  userId: string | null;
  roles: readonly Role[];
  /** submitters.id when the actor is a filmmaker/distributor */
  submitterId?: string | null;
  /** jurors.id when the actor is a juror */
  jurorId?: string | null;
}

export interface ResourceRef {
  type: Resource;
  /** owning submitter (films, orders, consents…) when relevant */
  submitterId?: string | null;
  /** film the row belongs to, when relevant */
  filmId?: string | null;
  /** for screener/juror scoping: ids of films assigned to the actor */
  assignedFilmIds?: readonly string[];
  /** user id stored on the row (decided_by, screener_user_id…) */
  ownerUserId?: string | null;
  /** row is public/published */
  isPublic?: boolean;
}

export interface Decision {
  allow: boolean;
  reason: string;
}

const STAFF: readonly Role[] = ["founder", "admin", "screener", "programmer", "support", "finance"];
const STAFF_READ: readonly Resource[] = [
  "submitter", "film", "entry", "film_asset", "consent", "film_note", "tag", "laurel", "decision", "document", "setting", "feature_flag",
];
const FINANCE: readonly Resource[] = ["product", "price", "coupon", "order", "invoice", "refund", "entitlement", "report"];
const SUPPORT_READ: readonly Resource[] = ["outbox", "email_event", "order"];
const OWNER_READ: readonly Resource[] = [
  "submitter", "film", "entry", "film_asset", "consent", "gate_film", "gate", "laurel", "order", "invoice", "entitlement", "outbox", "result", "screening_decision",
];
const OWNER_WRITE: readonly Resource[] = ["film", "film_asset", "consent", "submitter"];
const JUROR_READ: readonly Resource[] = ["film", "film_asset", "jury_assignment", "honour"];
const JURY_BLIND: readonly Resource[] = ["vote", "gate_film", "gate", "order", "invoice", "entitlement", "submitter", "result", "fraud_alert"];
const PUBLIC_READ: readonly Resource[] = ["film", "film_asset", "honour", "site_page", "faq", "journal_post", "programme_item", "result", "laurel"];

const has = (actor: Actor, ...roles: Role[]) => roles.some((r) => actor.roles.includes(r));
const allow = (reason: string): Decision => ({ allow: true, reason });
const deny = (reason: string): Decision => ({ allow: false, reason });

export function decideAccess(actor: Actor, action: Action, res: ResourceRef): Decision {
  // 1. Founder: everything.
  if (has(actor, "founder")) return allow("founder");

  // 2. Jury blindness beats everything else (a juror who is also staff must use a separate account).
  if (has(actor, "juror") && JURY_BLIND.includes(res.type)) return deny("jury_blind");

  // 3. Admin: everything except founder-only switches and finance payouts.
  if (has(actor, "admin")) {
    if (action === "flip_flag") return deny("flags_are_founder_only");
    if (action === "sign_off" && res.type === "result") return deny("results_sign_off_is_founder_only");
    if (res.type === "audit_log" && action !== "read") return deny("audit_log_append_only");
    return allow("admin");
  }

  // 4. Append-only / immutable rows for everyone else.
  if (res.type === "audit_log") return action === "read" && has(actor, ...STAFF) ? allow("staff_read_audit") : deny("audit_log");
  if (res.type === "invoice" && (action === "update" || action === "delete")) return deny("invoices_are_immutable");
  if (res.type === "vote" && action !== "read") return deny("votes_only_from_stripe_webhook");

  // 5. Staff roles.
  if (has(actor, "finance") && FINANCE.includes(res.type)) return allow("finance");
  if (has(actor, "support") && SUPPORT_READ.includes(res.type) && action === "read") return allow("support_read");
  if (has(actor, "support") && (res.type === "task" || res.type === "crm_activity" || res.type === "film_note")) return allow("support");
  if (has(actor, "programmer") && (res.type === "programme_item")) return allow("programmer");
  if (has(actor, "screener")) {
    const assigned = !!res.filmId && (res.assignedFilmIds ?? []).includes(res.filmId);
    if (res.type === "screening_assignment" && res.ownerUserId === actor.userId) return allow("own_assignment");
    if (res.type === "screening_flag" && action === "read" && assigned) return allow("assigned_flag");
    if (res.type === "screening_decision" && assigned && (action === "read" || action === "create" || action === "decide")) return allow("assigned_decision");
  }
  if (has(actor, ...STAFF)) {
    if (action === "read" && STAFF_READ.includes(res.type)) return allow("staff_read");
    if ((res.type === "task" || res.type === "crm_activity" || res.type === "film_note")) return allow("staff_notes");
  }

  // 6. Juror (blind): only assigned films, own scores/conflicts.
  if (has(actor, "juror")) {
    const assigned = !!res.filmId && (res.assignedFilmIds ?? []).includes(res.filmId);
    if (res.type === "score" || res.type === "conflict") return assigned ? allow("juror_own_scoring") : deny("not_assigned");
    if (JUROR_READ.includes(res.type) && action === "read") return res.type === "honour" || assigned ? allow("juror_read") : deny("not_assigned");
    return deny("juror_scope");
  }

  // 7. Filmmaker / distributor: own rows only.
  if (has(actor, "filmmaker", "distributor") && actor.submitterId) {
    const own = res.submitterId === actor.submitterId;
    if (res.type === "gate" && action === "read") return allow("filmmaker_gate_read");
    if (!own) return deny("not_owner");
    if (action === "read" && OWNER_READ.includes(res.type)) return allow("owner_read");
    if ((action === "update" || action === "create") && OWNER_WRITE.includes(res.type)) return allow("owner_write");
    return deny("owner_scope");
  }

  // 8. Public.
  if (action === "read" && PUBLIC_READ.includes(res.type) && res.isPublic) return allow("public_read");
  return deny("default_deny");
}

export function assertAccess(actor: Actor, action: Action, res: ResourceRef): void {
  const d = decideAccess(actor, action, res);
  if (!d.allow) {
    const err = new Error(`access denied: ${action} ${res.type} (${d.reason})`);
    (err as Error & { status: number }).status = 403;
    throw err;
  }
}
