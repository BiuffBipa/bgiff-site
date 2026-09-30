/**
 * Gates engine — pure TypeScript mirror of the SQL functions in
 * supabase/migrations/20260930000600_gates.sql (votes_apply, close_gate, gate_should_close).
 *
 * The database is the source of truth and enforces these rules in triggers; this module exists so
 * the app can (a) pre-validate a checkout before creating a Stripe session, (b) simulate/preview a
 * gate close in the admin UI, and (c) unit-test the rules. Every number comes from a `gates` row.
 */

import { orderTotals, type Cents, type OrderTotals } from "../money";

export type GateStatus = "draft" | "scheduled" | "open" | "closing" | "closed" | "cancelled";
export type GateFilmStatus = "active" | "through" | "eliminated" | "withdrawn";

export interface GateConfig {
  id: string;
  n: number;
  threshold: number;
  capacity: number;
  votePriceCents: Cents;
  bookingFeeCents: Cents;
  vatRateBp: number;
  opensAt: Date | null;
  closesAt: Date | null;
  status: GateStatus;
}

export interface GateFilmState {
  filmId: string;
  votes: number;
  status: GateFilmStatus;
  throughAt: Date | null;
  lastVoteAt: Date | null;
  createdAt: Date;
}

export type VoteOutcome =
  | { kind: "counted"; film: GateFilmState; becameThrough: boolean }
  | { kind: "rejected"; reason: "gate_not_open" | "film_not_active" | "invalid_qty"; film: GateFilmState | null };

/** Mirror of votes_apply(): count a paid vote, promote to `through` at threshold. */
export function applyVote(gate: GateConfig, film: GateFilmState | null, qty: number, at: Date): VoteOutcome {
  if (!Number.isInteger(qty) || qty <= 0) return { kind: "rejected", reason: "invalid_qty", film };
  if (gate.status !== "open") return { kind: "rejected", reason: "gate_not_open", film };
  if (!film || film.status !== "active") return { kind: "rejected", reason: "film_not_active", film };
  const votes = film.votes + qty;
  const becameThrough = votes >= gate.threshold;
  return {
    kind: "counted",
    becameThrough,
    film: {
      ...film,
      votes,
      lastVoteAt: at,
      status: becameThrough ? "through" : "active",
      throughAt: becameThrough ? at : film.throughAt,
    },
  };
}

/** Mirror of votes_reverse() for a refund/chargeback while the gate is open. */
export function reverseVote(gate: GateConfig, film: GateFilmState, qty: number): GateFilmState {
  const votes = Math.max(film.votes - qty, 0);
  const dropsBack = gate.status === "open" && film.status === "through" && votes < gate.threshold;
  return { ...film, votes, status: dropsBack ? "active" : film.status, throughAt: dropsBack ? null : film.throughAt };
}

export function throughCount(films: GateFilmState[]): number {
  return films.filter((f) => f.status === "through").length;
}

/** Mirror of gate_should_close(). */
export function shouldClose(gate: GateConfig, films: GateFilmState[], now: Date): boolean {
  if (gate.status !== "open") return false;
  if (throughCount(films) >= gate.capacity) return true;
  return gate.closesAt !== null && now.getTime() >= gate.closesAt.getTime();
}

/** Deterministic ranking used at close: votes desc, earliest last vote first, then earliest entry. */
export function rankActive(films: GateFilmState[]): GateFilmState[] {
  return films
    .filter((f) => f.status === "active")
    .slice()
    .sort((a, b) => {
      if (b.votes !== a.votes) return b.votes - a.votes;
      const la = a.lastVoteAt?.getTime() ?? Number.POSITIVE_INFINITY;
      const lb = b.lastVoteAt?.getTime() ?? Number.POSITIVE_INFINITY;
      if (la !== lb) return la - lb;
      return a.createdAt.getTime() - b.createdAt.getTime();
    });
}

export interface CloseResult {
  through: GateFilmState[];
  promotedByRank: GateFilmState[];
  eliminated: GateFilmState[];
  ranks: Map<string, number>;
}

/** Mirror of close_gate(): fill remaining capacity by rank, eliminate the rest. Pure — returns the new states. */
export function closeGate(gate: GateConfig, films: GateFilmState[], now: Date): CloseResult {
  const alreadyThrough = films
    .filter((f) => f.status === "through")
    .sort((a, b) => (a.throughAt?.getTime() ?? 0) - (b.throughAt?.getTime() ?? 0));
  const slots = Math.max(gate.capacity - alreadyThrough.length, 0);
  const ranked = rankActive(films);
  const promotedByRank = ranked.slice(0, slots).map((f) => ({ ...f, status: "through" as const, throughAt: now }));
  const eliminated = ranked.slice(slots).map((f) => ({ ...f, status: "eliminated" as const }));
  const ranks = new Map<string, number>();
  let r = 1;
  for (const f of alreadyThrough) ranks.set(f.filmId, r++);
  for (const f of promotedByRank) ranks.set(f.filmId, r++);
  for (const f of eliminated) ranks.set(f.filmId, r++);
  return { through: [...alreadyThrough, ...promotedByRank], promotedByRank, eliminated, ranks };
}

export interface VoteQuote extends OrderTotals {
  qty: number;
  unitGross: Cents;
}

/** Price a vote checkout for a gate (qty × price + one booking fee), all gross incl. VAT. */
export function quoteVotes(gate: GateConfig, qty: number, maxQtyPerCheckout: number): VoteQuote {
  if (!Number.isInteger(qty) || qty <= 0) throw new RangeError("qty must be a positive integer");
  if (qty > maxQtyPerCheckout) throw new RangeError(`qty exceeds the per-checkout cap of ${maxQtyPerCheckout}`);
  const totals = orderTotals([{ qty, unitGross: gate.votePriceCents, vatRateBp: gate.vatRateBp }], gate.bookingFeeCents, gate.vatRateBp);
  return { ...totals, qty, unitGross: gate.votePriceCents };
}

/** Films that enter gate N+1 after gate N closes (votes reset to zero). */
export function seedNextGate(closed: CloseResult, now: Date): GateFilmState[] {
  return closed.through.map((f) => ({ filmId: f.filmId, votes: 0, status: "active", throughAt: null, lastVoteAt: null, createdAt: now }));
}
