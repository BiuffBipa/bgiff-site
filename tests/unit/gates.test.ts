import { describe, expect, it } from "vitest";
import { applyVote, closeGate, quoteVotes, reverseVote, seedNextGate, shouldClose, type GateConfig, type GateFilmState } from "@/lib/platform/gates/engine";

const t0 = new Date("2026-12-01T00:00:00Z");
const gate: GateConfig = { id: "g1", n: 1, threshold: 3, capacity: 2, votePriceCents: 100, bookingFeeCents: 49, vatRateBp: 1900, opensAt: t0, closesAt: new Date("2026-12-08T00:00:00Z"), status: "open" };
const film = (id: string, votes = 0, i = 0): GateFilmState => ({ filmId: id, votes, status: "active", throughAt: null, lastVoteAt: null, createdAt: new Date(t0.getTime() + i) });

describe("gates engine (mirrors SQL)", () => {
  it("counts votes and promotes at threshold", () => {
    const r1 = applyVote(gate, film("a"), 2, t0);
    expect(r1.kind).toBe("counted");
    if (r1.kind !== "counted") return;
    expect(r1.film.votes).toBe(2);
    expect(r1.becameThrough).toBe(false);
    const r2 = applyVote(gate, r1.film, 1, t0);
    if (r2.kind !== "counted") throw new Error();
    expect(r2.film.status).toBe("through");
    expect(r2.becameThrough).toBe(true);
    expect(applyVote(gate, r2.film, 1, t0)).toMatchObject({ kind: "rejected", reason: "film_not_active" });
  });
  it("rejects votes on a closed gate or invalid qty", () => {
    expect(applyVote({ ...gate, status: "draft" }, film("a"), 1, t0)).toMatchObject({ kind: "rejected", reason: "gate_not_open" });
    expect(applyVote(gate, film("a"), 0, t0)).toMatchObject({ kind: "rejected", reason: "invalid_qty" });
    expect(applyVote(gate, null, 1, t0)).toMatchObject({ kind: "rejected", reason: "film_not_active" });
  });
  it("refund drops a film back under threshold while open", () => {
    const through: GateFilmState = { ...film("a", 3), status: "through", throughAt: t0 };
    expect(reverseVote(gate, through, 1)).toMatchObject({ votes: 2, status: "active", throughAt: null });
    expect(reverseVote({ ...gate, status: "closed" }, through, 1)).toMatchObject({ votes: 2, status: "through" });
  });
  it("closes on capacity or time", () => {
    const films = [{ ...film("a", 3), status: "through" as const }, { ...film("b", 3), status: "through" as const }, film("c", 1)];
    expect(shouldClose(gate, films, t0)).toBe(true);
    expect(shouldClose(gate, [film("a")], t0)).toBe(false);
    expect(shouldClose(gate, [film("a")], new Date("2026-12-09T00:00:00Z"))).toBe(true);
  });
  it("fills remaining slots by rank, ties by earliest last vote then entry order", () => {
    const l1 = new Date(t0.getTime() + 1000), l2 = new Date(t0.getTime() + 2000);
    const films: GateFilmState[] = [
      { ...film("a", 3, 0), status: "through", throughAt: t0 },
      { ...film("b", 2, 1), lastVoteAt: l2 },
      { ...film("c", 2, 2), lastVoteAt: l1 }, // same votes as b, voted earlier → wins the tie
      film("d", 0, 3),
    ];
    const r = closeGate(gate, films, l2);
    expect(r.through.map((f) => f.filmId)).toEqual(["a", "c"]);
    expect(r.eliminated.map((f) => f.filmId)).toEqual(["b", "d"]);
    expect([...r.ranks.entries()]).toEqual([["a", 1], ["c", 2], ["b", 3], ["d", 4]]);
    expect(seedNextGate(r, l2)).toEqual([
      { filmId: "a", votes: 0, status: "active", throughAt: null, lastVoteAt: null, createdAt: l2 },
      { filmId: "c", votes: 0, status: "active", throughAt: null, lastVoteAt: null, createdAt: l2 },
    ]);
  });
  it("never promotes beyond capacity even with many through", () => {
    const films = ["a", "b", "c"].map((id) => ({ ...film(id, 3), status: "through" as const, throughAt: t0 }));
    const r = closeGate(gate, [...films, film("d", 2)], t0);
    expect(r.through).toHaveLength(3); // already through stay through (capacity reached late by race)
    expect(r.promotedByRank).toHaveLength(0);
    expect(r.eliminated.map((f) => f.filmId)).toEqual(["d"]);
  });
  it("quotes qty × price + one fee, gross incl. VAT", () => {
    const q = quoteVotes(gate, 5, 500);
    expect(q.gross).toBe(549);
    expect(q.fee).toBe(49);
    expect(q.net + q.vat).toBe(549);
    expect(() => quoteVotes(gate, 501, 500)).toThrow(RangeError);
  });
});
