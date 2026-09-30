/**
 * Money helpers. All amounts are integer cents. Never use floats for money.
 * Prices are stored GROSS (incl. VAT) because that is what consumers see (PAngV);
 * net and VAT are derived per line with half-up rounding and the sum is reconciled
 * so that net + vat === gross for every line.
 */

export type Cents = number;

export function assertCents(value: unknown, label = "amount"): asserts value is Cents {
  if (typeof value !== "number" || !Number.isInteger(value) || !Number.isFinite(value)) {
    throw new TypeError(`${label} must be an integer number of cents, got ${String(value)}`);
  }
}

/** Basis points → ratio (1900 → 0.19). */
export function bpToRatio(bp: number): number {
  if (!Number.isInteger(bp) || bp < 0 || bp > 10_000) throw new RangeError(`invalid basis points: ${bp}`);
  return bp / 10_000;
}

/** Round half away from zero, on integers only. */
function roundHalfUp(x: number): number {
  return x < 0 ? -Math.round(-x) : Math.round(x);
}

export interface VatSplit {
  gross: Cents;
  net: Cents;
  vat: Cents;
  vatRateBp: number;
}

/** Split a gross amount into net + VAT. gross = net + vat always holds. */
export function splitGross(gross: Cents, vatRateBp: number): VatSplit {
  assertCents(gross, "gross");
  const ratio = bpToRatio(vatRateBp);
  const net = roundHalfUp(gross / (1 + ratio));
  return { gross, net, vat: gross - net, vatRateBp };
}

/** Gross from a net amount (used for B2B quotes where net is the anchor). */
export function grossFromNet(net: Cents, vatRateBp: number): VatSplit {
  assertCents(net, "net");
  const vat = roundHalfUp(net * bpToRatio(vatRateBp));
  return { gross: net + vat, net, vat, vatRateBp };
}

export interface LineInput {
  qty: number;
  unitGross: Cents;
  vatRateBp: number;
}

export interface LineTotals extends VatSplit {
  qty: number;
  unitGross: Cents;
}

export function lineTotals(line: LineInput): LineTotals {
  if (!Number.isInteger(line.qty) || line.qty <= 0) throw new RangeError(`qty must be a positive integer, got ${line.qty}`);
  assertCents(line.unitGross, "unitGross");
  const split = splitGross(line.qty * line.unitGross, line.vatRateBp);
  return { ...split, qty: line.qty, unitGross: line.unitGross };
}

export interface OrderTotals {
  net: Cents;
  vat: Cents;
  fee: Cents;
  gross: Cents; // what the buyer pays: sum(lines gross) + fee gross
  lines: LineTotals[];
  feeSplit: VatSplit;
}

/** Sum lines + one booking fee (gross, same VAT rate as given). */
export function orderTotals(lines: LineInput[], bookingFeeGross: Cents, feeVatRateBp: number): OrderTotals {
  assertCents(bookingFeeGross, "bookingFee");
  const computed = lines.map(lineTotals);
  const feeSplit = splitGross(bookingFeeGross, feeVatRateBp);
  const net = computed.reduce((s, l) => s + l.net, 0) + feeSplit.net;
  const vat = computed.reduce((s, l) => s + l.vat, 0) + feeSplit.vat;
  const gross = computed.reduce((s, l) => s + l.gross, 0) + feeSplit.gross;
  return { net, vat, fee: feeSplit.gross, gross, lines: computed, feeSplit };
}

/** Apply a coupon to a gross subtotal. Never below zero. */
export function applyCoupon(subtotalGross: Cents, coupon: { kind: "percent" | "fixed"; value: number }): Cents {
  assertCents(subtotalGross, "subtotal");
  if (coupon.kind === "percent") {
    if (coupon.value < 1 || coupon.value > 100) throw new RangeError("percent coupon must be 1..100");
    return Math.max(0, subtotalGross - roundHalfUp((subtotalGross * coupon.value) / 100));
  }
  assertCents(coupon.value, "coupon value");
  return Math.max(0, subtotalGross - coupon.value);
}

/** Format cents for display, e.g. 12345 → "€123.45". Locale-agnostic on purpose (UI decides). */
export function formatCents(cents: Cents, currency = "EUR"): string {
  assertCents(cents);
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const symbol = currency === "EUR" ? "€" : `${currency} `;
  return `${sign}${symbol}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, "0")}`;
}
