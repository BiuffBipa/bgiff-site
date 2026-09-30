import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { parseCsv, parseCsvRecords } from "@/lib/platform/intake/csv";
import { mapRow, parseDateIso, parseMoneyCents, parseRuntimeSeconds, type MappingRule } from "@/lib/platform/intake/mapper";
import { decideMerge, findDuplicates, normalizeTitle } from "@/lib/platform/intake/dedupe";
import { resolveCategoryAlias } from "@/lib/platform/categories";

const fixture = (name: string) => readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8");
// Same JSON shape as import_mappings.mapping (seed); a subset is enough to prove the mechanics.
const ffMapping: MappingRule[] = [
  { target: "entry.external_id", source: ["Submission ID", "Tracking Number"], required: true },
  { target: "entry.submitted_at", source: ["Submission Date"], transform: "date" },
  { target: "entry.category_raw", source: ["Category"], required: true },
  { target: "entry.fee_cents", source: ["Entry Fee"], transform: "money_cents" },
  { target: "submitter.email", source: ["Submitter Email", "Contact Email"], transform: "email", required: true },
  { target: "submitter.country", source: ["Country"], transform: "country" },
  { target: "film.title", source: ["Project Title", "Title"], required: true },
  { target: "film.runtime_seconds", source: ["Runtime"], transform: "runtime" },
  { target: "film.completion_year", source: ["Completion Date"], transform: "year" },
  { target: "film.country_of_origin", source: ["Country of Origin"], transform: "country" },
  { target: "film.genres", source: ["Genres"], transform: "list" },
  { target: "film.is_first_film", source: ["First-time Filmmaker"], transform: "bool" },
  { target: "people.directors", source: ["Directors"], transform: "list" },
  { target: "assets.screener_url", source: ["Screener"] },
  { target: "assets.screener_password", source: ["Screener Password"] },
  { target: "film.ai_declaration", source: ["AI Disclosure"] }, // absent in this file → reported as unmatched
];
const fhMapping: MappingRule[] = [
  { target: "entry.external_id", source: ["ID"], required: true },
  { target: "entry.submitted_at", source: ["Submission date"], transform: "date" },
  { target: "entry.category_raw", source: ["Section"], required: true },
  { target: "submitter.email", source: ["Email"], transform: "email", required: true },
  { target: "film.title", source: ["Title"], required: true },
  { target: "film.runtime_seconds", source: ["Duration"], transform: "runtime" },
  { target: "film.synopsis", source: ["Synopsis"] },
  { target: "film.has_subtitles", source: ["Subtitles"], transform: "bool" },
];

describe("csv parser", () => {
  it("handles quotes, embedded commas and newlines, BOM and CRLF", () => {
    const recs = parseCsvRecords('﻿a,b\r\n1,"x, ""y""\nz"\r\n');
    expect(recs).toEqual([["a", "b"], ["1", 'x, "y"\nz']]);
  });
  it("reports ragged rows or merges overflow (FestHome unquoted commas)", () => {
    const text = "ID,Title,Synopsis,Email\n1,Film,A night, a car, a city,x@example.com\n";
    expect(parseCsv(text, { raggedRowStrategy: "error" }).errors).toHaveLength(1);
    const merged = parseCsv(text, { raggedRowStrategy: "merge-overflow", overflowColumn: "Synopsis" });
    expect(merged.rows[0].cells).toEqual({ ID: "1", Title: "Film", Synopsis: "A night, a car, a city", Email: "x@example.com" });
    expect(merged.rows[0].warnings).toContain("merged_overflow_cells");
  });
  it("detects semicolon delimiter", () => {
    expect(parseCsv("a;b\n1;2\n").rows[0].cells).toEqual({ a: "1", b: "2" });
  });
});

describe("mapper transforms", () => {
  it("runtime", () => {
    expect(parseRuntimeSeconds("00:14:30")).toBe(870);
    expect(parseRuntimeSeconds("1:22:05")).toBe(4925);
    expect(parseRuntimeSeconds("14:30")).toBe(870);
    expect(parseRuntimeSeconds("92 min")).toBe(5520);
    expect(parseRuntimeSeconds("1h 32m")).toBe(5520);
    expect(parseRuntimeSeconds("14")).toBe(840);
    expect(parseRuntimeSeconds("5400")).toBe(5400);
    expect(() => parseRuntimeSeconds("n/a")).toThrow();
  });
  it("dates", () => {
    expect(parseDateIso("2026-09-27")).toBe("2026-09-27T00:00:00.000Z");
    expect(parseDateIso("27/09/2026")).toBe("2026-09-27T00:00:00.000Z");
    expect(parseDateIso("Sep 27, 2026")).toMatch(/^2026-09-2[67]T/);
    expect(() => parseDateIso("31/31/2026")).toThrow();
  });
  it("money", () => {
    expect(parseMoneyCents("$0.00")).toBe(0);
    expect(parseMoneyCents("25,00 €")).toBe(2500);
    expect(parseMoneyCents("Free")).toBe(0);
    expect(parseMoneyCents("1,250.50")).toBe(125050);
  });
});

describe("filmfreeway preset on a sample export", () => {
  const { headers, rows } = parseCsv(fixture("filmfreeway_sample.csv"));
  it("maps the first row", () => {
    const out = mapRow(rows[0].cells, headers, ffMapping);
    expect(out.missingRequired).toEqual([]);
    expect(out.unmatchedRules).toEqual(["film.ai_declaration"]);
    expect(out.record.entry.external_id).toBe("FF-1001");
    expect(out.record.submitter.email).toBe("anna@example.com");
    expect(out.record.film.runtime_seconds).toBe(870);
    expect(out.record.film.completion_year).toBe(2026);
    expect(out.record.film.country_of_origin).toBe("DE");
    expect(out.record.film.genres).toEqual(["Drama", "Family"]);
    expect(out.record.film.is_first_film).toBe(true);
    expect(out.record.entry.fee_cents).toBe(0);
    expect(out.record.assets.screener_password).toBe("gate2026");
  });
  it("keeps multi-line synopsis and lower-cases emails", () => {
    const out = mapRow(rows[1].cells, headers, ffMapping);
    expect(out.record.submitter.email).toBe("reza@example.com");
    expect(rows[1].cells["Synopsis"]).toContain("\n");
    expect(out.record.film.country_of_origin).toBe("IR");
  });
});

describe("festhome preset on a sample export", () => {
  const { headers, rows, errors } = parseCsv(fixture("festhome_sample.csv"), { raggedRowStrategy: "merge-overflow", overflowColumn: "Synopsis" });
  it("survives an unquoted comma in the synopsis", () => {
    expect(errors).toEqual([]);
    const out = mapRow(rows[0].cells, headers, fhMapping);
    expect(out.record.film.synopsis).toBe("A short about a door that never opens, and the sister who waits behind it.");
    expect(out.record.entry.submitted_at).toBe("2026-09-27T00:00:00.000Z");
    expect(out.record.film.has_subtitles).toBe(true);
    expect(out.record.film.runtime_seconds).toBe(870);
  });
});

describe("dedupe", () => {
  it("normalises titles like SQL", () => {
    expect(normalizeTitle("The Quiet Gate")).toBe("quiet gate");
    expect(normalizeTitle("Das stille Tor!")).toBe("stille tor");
    expect(normalizeTitle("  Salt & Static ")).toBe("salt static");
    expect(normalizeTitle("Café Été")).toBe("cafe ete");
  });
  it("merges the same work across platforms/categories for the same submitter only", () => {
    const existing = [{ filmId: "f1", submitterEmail: "anna@example.com", normalizedTitle: "quiet gate", runtimeSeconds: 870 }];
    const opts = { runtimeToleranceSeconds: 120, fuzzyThreshold: 0.85 };
    expect(decideMerge(findDuplicates({ filmId: "x", submitterEmail: "ANNA@example.com", normalizedTitle: "quiet gate", runtimeSeconds: 900 }, existing, opts))).toEqual({ action: "merge", filmId: "f1" });
    expect(decideMerge(findDuplicates({ filmId: "x", submitterEmail: "other@example.com", normalizedTitle: "quiet gate", runtimeSeconds: 870 }, existing, opts))).toEqual({ action: "create" });
    expect(decideMerge(findDuplicates({ filmId: "x", submitterEmail: "anna@example.com", normalizedTitle: "quiet gates", runtimeSeconds: 870 }, existing, opts)).action).toBe("review");
    expect(decideMerge(findDuplicates({ filmId: "x", submitterEmail: "anna@example.com", normalizedTitle: "quiet gate", runtimeSeconds: 5000 }, existing, opts))).toEqual({ action: "create" });
  });
  it("resolves platform category names through aliases", () => {
    const cats = [{ key: "narrative_short", name: "Narrative Short", aliases: ["Short Film"] }, { key: "lgbtq", name: "LGBTQ+", aliases: [] }];
    expect(resolveCategoryAlias("short film", cats)).toBe("narrative_short");
    expect(resolveCategoryAlias("LGBTQ+", cats)).toBe("lgbtq");
    expect(resolveCategoryAlias("Feature Film", cats)).toBeNull();
  });
});
