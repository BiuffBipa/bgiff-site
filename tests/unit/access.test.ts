import { describe, expect, it } from "vitest";
import { decideAccess, type Actor } from "@/lib/platform/access";

const founder: Actor = { userId: "u0", roles: ["founder"] };
const admin: Actor = { userId: "u1", roles: ["admin"] };
const juror: Actor = { userId: "u2", roles: ["juror"], jurorId: "j1" };
const maker: Actor = { userId: "u3", roles: ["filmmaker"], submitterId: "s1" };
const screener: Actor = { userId: "u5", roles: ["screener"] };
const finance: Actor = { userId: "u6", roles: ["finance"] };
const anon: Actor = { userId: null, roles: ["public"] };

describe("decideAccess", () => {
  it("founder does everything, admin cannot flip flags or sign off results", () => {
    expect(decideAccess(founder, "flip_flag", { type: "feature_flag" }).allow).toBe(true);
    expect(decideAccess(admin, "flip_flag", { type: "feature_flag" }).allow).toBe(false);
    expect(decideAccess(admin, "sign_off", { type: "result" }).allow).toBe(false);
    expect(decideAccess(admin, "update", { type: "gate" }).allow).toBe(true);
  });
  it("jury is blind to votes, orders and identities", () => {
    for (const type of ["vote", "gate_film", "order", "entitlement", "submitter"] as const) {
      expect(decideAccess(juror, "read", { type }).allow).toBe(false);
    }
    expect(decideAccess(juror, "read", { type: "film", filmId: "f1", assignedFilmIds: ["f1"] }).allow).toBe(true);
    expect(decideAccess(juror, "read", { type: "film", filmId: "f2", assignedFilmIds: ["f1"] }).allow).toBe(false);
    expect(decideAccess(juror, "create", { type: "score", filmId: "f1", assignedFilmIds: ["f1"] }).allow).toBe(true);
    // a juror who is also admin stays blind
    expect(decideAccess({ ...admin, roles: ["admin", "juror"] }, "read", { type: "vote" }).allow).toBe(false);
  });
  it("filmmakers see and edit only their own rows", () => {
    expect(decideAccess(maker, "read", { type: "film", submitterId: "s1" }).allow).toBe(true);
    expect(decideAccess(maker, "read", { type: "film", submitterId: "s2" }).allow).toBe(false);
    expect(decideAccess(maker, "update", { type: "film", submitterId: "s1" }).allow).toBe(true);
    expect(decideAccess(maker, "read", { type: "vote", submitterId: "s1" }).allow).toBe(false);
    expect(decideAccess(maker, "read", { type: "gate_film", submitterId: "s1" }).allow).toBe(true);
    expect(decideAccess(maker, "delete", { type: "film", submitterId: "s1" }).allow).toBe(false);
  });
  it("screener acts only on assigned films; finance owns commerce; nobody edits invoices or votes", () => {
    expect(decideAccess(screener, "decide", { type: "screening_decision", filmId: "f1", assignedFilmIds: ["f1"] }).allow).toBe(true);
    expect(decideAccess(screener, "decide", { type: "screening_decision", filmId: "f9", assignedFilmIds: ["f1"] }).allow).toBe(false);
    expect(decideAccess(screener, "read", { type: "order" }).allow).toBe(false);
    expect(decideAccess(finance, "create", { type: "refund" }).allow).toBe(true);
    expect(decideAccess(finance, "update", { type: "invoice" }).allow).toBe(false);
    expect(decideAccess(finance, "create", { type: "vote" }).allow).toBe(false);
    expect(decideAccess(finance, "update", { type: "audit_log" }).allow).toBe(false);
  });
  it("public reads only published things", () => {
    expect(decideAccess(anon, "read", { type: "film", isPublic: true }).allow).toBe(true);
    expect(decideAccess(anon, "read", { type: "film", isPublic: false }).allow).toBe(false);
    expect(decideAccess(anon, "read", { type: "order" }).allow).toBe(false);
  });
});
