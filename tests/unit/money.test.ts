import { describe, expect, it } from "vitest";
import { applyCoupon, formatCents, grossFromNet, lineTotals, orderTotals, splitGross } from "@/lib/platform/money";

describe("money", () => {
  it("splits gross into net + vat with no drift", () => {
    for (const gross of [1, 49, 100, 199, 349, 1999, 4900, 123456]) {
      const s = splitGross(gross, 1900);
      expect(s.net + s.vat).toBe(gross);
      expect(s.net).toBeGreaterThanOrEqual(0);
    }
    expect(splitGross(119, 1900)).toEqual({ gross: 119, net: 100, vat: 19, vatRateBp: 1900 });
    expect(splitGross(100, 0)).toEqual({ gross: 100, net: 100, vat: 0, vatRateBp: 0 });
  });
  it("gross from net", () => {
    expect(grossFromNet(100, 1900).gross).toBe(119);
  });
  it("rejects non-integer cents", () => {
    expect(() => splitGross(1.5, 1900)).toThrow(TypeError);
    expect(() => lineTotals({ qty: 0, unitGross: 100, vatRateBp: 1900 })).toThrow(RangeError);
  });
  it("order totals include one booking fee", () => {
    const t = orderTotals([{ qty: 3, unitGross: 100, vatRateBp: 1900 }], 49, 1900);
    expect(t.gross).toBe(349);
    expect(t.fee).toBe(49);
    expect(t.net + t.vat).toBe(349);
  });
  it("coupons never go below zero", () => {
    expect(applyCoupon(1000, { kind: "percent", value: 10 })).toBe(900);
    expect(applyCoupon(1000, { kind: "fixed", value: 5000 })).toBe(0);
    expect(() => applyCoupon(1000, { kind: "percent", value: 150 })).toThrow();
  });
  it("formats", () => {
    expect(formatCents(12345)).toBe("€123.45");
    expect(formatCents(-5)).toBe("-€0.05");
  });
});
