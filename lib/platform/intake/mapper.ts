/**
 * Configurable column mapper. The mapping is DATA (import_mappings.mapping / options, seeded per
 * platform and editable by admins); this module only interprets it. Presets in the seed are
 * best-effort guesses at FilmFreeway / FestHome export headers until the real 27 Sep exports are
 * attached — headers match case- and whitespace-insensitively, and unknown headers are reported.
 */
import { normalizeHeader } from "./csv";

export type Transform =
  | "trim" | "email" | "lower" | "int" | "year" | "runtime" | "date" | "list" | "country" | "country_list" | "bool" | "money_cents";

export interface MappingRule {
  target: string;          // e.g. "film.title", "submitter.email", "people.directors"
  source: string[];        // candidate headers, first match wins
  transform?: Transform;
  required?: boolean;
  default?: unknown;
}

export interface MappingOptions {
  delimiter?: string;
  raggedRowStrategy?: "error" | "pad" | "merge-overflow";
  dateFormats?: string[];
  listSeparators?: string[];
}

export interface MappedRecord {
  submitter: { email?: string; name?: string; country?: string; phone?: string };
  film: {
    title?: string; original_title?: string; runtime_seconds?: number; completion_year?: number; country_of_origin?: string;
    countries?: string[]; languages?: string[]; genres?: string[]; synopsis?: string; logline?: string; premiere_status?: string;
    is_student?: boolean; is_first_film?: boolean; has_subtitles?: boolean; ai_declaration?: string;
  };
  entry: {
    external_id?: string; external_url?: string; category_raw?: string; submitted_at?: string; platform_status?: string;
    judging_status?: string; fee_cents?: number;
  };
  people: { directors?: string[]; writers?: string[]; producers?: string[]; cast?: string[] };
  assets: { screener_url?: string; screener_password?: string; poster_url?: string; trailer_url?: string };
}

export interface MapOutcome {
  record: MappedRecord;
  missingRequired: string[];
  unmatchedRules: string[];   // rules whose headers were not found in this file
  warnings: string[];
}

export function resolveHeaders(headers: string[], mapping: MappingRule[]): { index: Map<string, string>; unmatched: string[] } {
  const byNorm = new Map(headers.map((h) => [normalizeHeader(h), h]));
  const index = new Map<string, string>();
  const unmatched: string[] = [];
  for (const rule of mapping) {
    const hit = rule.source.map(normalizeHeader).find((s) => byNorm.has(s));
    if (hit) index.set(rule.target, byNorm.get(hit)!);
    else unmatched.push(rule.target);
  }
  return { index, unmatched };
}

export function mapRow(cells: Record<string, string>, headers: string[], mapping: MappingRule[], options: MappingOptions = {}): MapOutcome {
  const { index, unmatched } = resolveHeaders(headers, mapping);
  const record: MappedRecord = { submitter: {}, film: {}, entry: {}, people: {}, assets: {} };
  const missingRequired: string[] = [];
  const warnings: string[] = [];
  for (const rule of mapping) {
    const header = index.get(rule.target);
    const rawValue = header ? cells[header] : undefined;
    let value: unknown = rawValue === undefined || rawValue === "" ? rule.default : rawValue;
    if (value !== undefined && value !== null && typeof value === "string") {
      try { value = applyTransform(value, rule.transform ?? "trim", options); }
      catch (e) { warnings.push(`${rule.target}: ${(e as Error).message}`); value = undefined; }
    }
    if ((value === undefined || value === null || value === "") && rule.required) missingRequired.push(rule.target);
    if (value !== undefined && value !== null && value !== "") setPath(record, rule.target, value);
  }
  return { record, missingRequired, unmatchedRules: unmatched, warnings };
}

function setPath(record: MappedRecord, target: string, value: unknown): void {
  const [group, field] = target.split(".") as [keyof MappedRecord, string];
  if (!(group in record)) throw new Error(`unknown target group ${group}`);
  (record[group] as Record<string, unknown>)[field] = value;
}

export function applyTransform(raw: string, transform: Transform, options: MappingOptions): unknown {
  const s = raw.trim();
  switch (transform) {
    case "trim": return s;
    case "lower": return s.toLowerCase();
    case "email": {
      const e = s.toLowerCase();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) throw new Error(`invalid email "${raw}"`);
      return e;
    }
    case "int": { const n = parseInt(s.replace(/[^\d-]/g, ""), 10); if (Number.isNaN(n)) throw new Error(`not an integer "${raw}"`); return n; }
    case "year": { const m = s.match(/(19|20)\d{2}/); if (!m) throw new Error(`no year in "${raw}"`); return parseInt(m[0], 10); }
    case "runtime": return parseRuntimeSeconds(s);
    case "date": return parseDateIso(s, options.dateFormats);
    case "list": return splitList(s, options.listSeparators);
    case "country": return normalizeCountry(s);
    case "country_list": return splitList(s, options.listSeparators).map(normalizeCountry).filter((c): c is string => !!c);
    case "bool": return parseBool(s);
    case "money_cents": return parseMoneyCents(s);
  }
}

/** "1:32:10" | "92 min" | "92:10" | "01:32" | "5400" (seconds when > 600 and no unit) → seconds */
export function parseRuntimeSeconds(s: string): number {
  const t = s.toLowerCase().trim();
  if (!t) throw new Error("empty runtime");
  const hms = t.match(/^(\d{1,2}):(\d{2}):(\d{2})$/);
  if (hms) return (+hms[1]) * 3600 + (+hms[2]) * 60 + (+hms[3]);
  const ms = t.match(/^(\d{1,3}):(\d{2})$/);
  if (ms) return (+ms[1]) * 60 + (+ms[2]);
  const hm = t.match(/(\d+)\s*h(?:ours?|rs?)?\s*(\d+)?\s*(?:m(?:in(?:utes?)?)?)?/);
  if (hm && /h/.test(t)) return (+hm[1]) * 3600 + (hm[2] ? +hm[2] : 0) * 60;
  const min = t.match(/(\d+(?:[.,]\d+)?)\s*(?:m(?:in(?:utes?)?)?\.?)?(?:\s|$)/);
  const sec = t.match(/(\d+)\s*s(?:ec(?:onds?)?)?/);
  if (sec && !min?.[0].includes("m")) { const m = t.match(/(\d+)\s*m/); return (m ? +m[1] * 60 : 0) + (+sec[1]); }
  if (min) {
    const value = parseFloat(min[1].replace(",", "."));
    if (!/[a-z]/.test(t) && value > 600) return Math.round(value); // bare seconds
    return Math.round(value * 60);
  }
  throw new Error(`unparseable runtime "${s}"`);
}

export function parseDateIso(s: string, _formats?: string[]): string {
  const t = s.trim();
  const iso = t.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?/);
  if (iso) return toIso(+iso[1], +iso[2], +iso[3], iso[4] ? +iso[4] : 0, iso[5] ? +iso[5] : 0);
  const dmy = t.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{4})/);
  if (dmy) {
    // dd/mm/yyyy (FestHome, EU) unless the first number cannot be a day
    const a = +dmy[1], b = +dmy[2];
    const [d, m] = a > 12 ? [a, b] : b > 12 ? [b, a] : [a, b];
    return toIso(+dmy[3], m, d);
  }
  const parsed = Date.parse(t); // "Sep 27, 2026", "September 27, 2026 10:14 AM"
  if (!Number.isNaN(parsed)) return new Date(parsed).toISOString();
  throw new Error(`unparseable date "${s}"`);
}

function toIso(y: number, m: number, d: number, hh = 0, mm = 0): string {
  const dt = new Date(Date.UTC(y, m - 1, d, hh, mm));
  if (dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) throw new Error(`invalid date ${y}-${m}-${d}`);
  return dt.toISOString();
}

export function splitList(s: string, separators = [",", ";", "|", "/", "\n", " & ", " and "]): string[] {
  let parts = [s];
  for (const sep of separators) parts = parts.flatMap((p) => p.split(sep));
  return [...new Set(parts.map((p) => p.trim()).filter(Boolean))];
}

export function parseBool(s: string): boolean {
  const t = s.trim().toLowerCase();
  if (["yes", "y", "true", "1", "ja", "sí", "si", "x", "✓"].includes(t)) return true;
  if (["no", "n", "false", "0", "nein", "", "-"].includes(t)) return false;
  throw new Error(`not a boolean "${s}"`);
}

/** "$25.00" | "25,00 €" | "0" | "Free" → cents */
export function parseMoneyCents(s: string): number {
  const t = s.trim().toLowerCase();
  if (!t || t === "free" || t === "waived" || t === "n/a") return 0;
  const num = t.replace(/[^\d.,-]/g, "");
  if (!num) throw new Error(`not money "${s}"`);
  const normalized = num.includes(",") && !num.includes(".") ? num.replace(",", ".") : num.replace(/,/g, "");
  const value = parseFloat(normalized);
  if (Number.isNaN(value)) throw new Error(`not money "${s}"`);
  return Math.round(value * 100);
}

const COUNTRY_ALIASES: Record<string, string> = {
  "united states": "US", "usa": "US", "u.s.a.": "US", "united states of america": "US", "us": "US",
  "united kingdom": "GB", "uk": "GB", "great britain": "GB", "england": "GB",
  "germany": "DE", "deutschland": "DE", "iran": "IR", "iran, islamic republic of": "IR", "islamic republic of iran": "IR",
  "france": "FR", "spain": "ES", "italy": "IT", "india": "IN", "china": "CN", "turkey": "TR", "türkiye": "TR",
  "brazil": "BR", "canada": "CA", "mexico": "MX", "russia": "RU", "russian federation": "RU", "south korea": "KR", "korea, republic of": "KR",
  "japan": "JP", "netherlands": "NL", "the netherlands": "NL", "poland": "PL", "portugal": "PT", "greece": "GR", "austria": "AT",
  "switzerland": "CH", "belgium": "BE", "sweden": "SE", "norway": "NO", "denmark": "DK", "finland": "FI", "ireland": "IE",
  "australia": "AU", "new zealand": "NZ", "argentina": "AR", "chile": "CL", "colombia": "CO", "peru": "PE", "egypt": "EG",
  "israel": "IL", "lebanon": "LB", "iraq": "IQ", "afghanistan": "AF", "pakistan": "PK", "bangladesh": "BD", "indonesia": "ID",
  "philippines": "PH", "vietnam": "VN", "viet nam": "VN", "thailand": "TH", "taiwan": "TW", "hong kong": "HK", "ukraine": "UA",
  "czech republic": "CZ", "czechia": "CZ", "hungary": "HU", "romania": "RO", "bulgaria": "BG", "serbia": "RS", "croatia": "HR",
  "south africa": "ZA", "nigeria": "NG", "kenya": "KE", "morocco": "MA", "tunisia": "TN", "algeria": "DZ",
  "united arab emirates": "AE", "uae": "AE", "saudi arabia": "SA", "qatar": "QA", "armenia": "AM", "georgia": "GE", "azerbaijan": "AZ",
};

/** Returns ISO-3166-1 alpha-2 when recognised, otherwise the cleaned original (never throws; intake review catches the rest). */
export function normalizeCountry(s: string): string | null {
  const t = s.trim();
  if (!t) return null;
  if (/^[A-Za-z]{2}$/.test(t)) return t.toUpperCase();
  return COUNTRY_ALIASES[t.toLowerCase()] ?? t;
}
