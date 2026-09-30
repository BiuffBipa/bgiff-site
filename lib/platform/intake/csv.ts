/**
 * Tolerant CSV parser (RFC 4180 + real-world exports):
 * - quoted fields with embedded commas, quotes ("") and newlines
 * - BOM, CRLF/LF/CR, trailing empty line, configurable delimiter (",", ";", "\t")
 * - ragged rows: "error" | "pad" | "merge-overflow" (FestHome breaks on unquoted commas in text:
 *   with merge-overflow the extra cells are folded back into the last text column)
 * Streams nothing (exports are ≤ a few MB); for 30k rows this is still < 1 s.
 */

export type RaggedRowStrategy = "error" | "pad" | "merge-overflow";

export interface CsvOptions {
  delimiter?: string;
  raggedRowStrategy?: RaggedRowStrategy;
  /** header row index (0-based); rows before it are skipped */
  headerRow?: number;
  /** when using merge-overflow, which column absorbs overflow (default: the longest text cell of the row) */
  overflowColumn?: string;
}

export interface CsvRow {
  index: number; // 0-based data row index (header excluded)
  cells: Record<string, string>;
  raw: string[];
  warnings: string[];
}

export interface CsvResult {
  headers: string[];
  rows: CsvRow[];
  errors: Array<{ index: number; message: string }>;
}

export function parseCsvRecords(text: string, delimiter = ","): string[][] {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const records: string[][] = [];
  let record: string[] = [];
  let field = "";
  let inQuotes = false;
  let i = 0;
  const n = text.length;
  while (i < n) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 2; continue; }
        inQuotes = false; i++; continue;
      }
      field += ch; i++; continue;
    }
    if (ch === '"') { inQuotes = true; i++; continue; }
    if (ch === delimiter) { record.push(field); field = ""; i++; continue; }
    if (ch === "\r") { if (text[i + 1] === "\n") i++; record.push(field); records.push(record); record = []; field = ""; i++; continue; }
    if (ch === "\n") { record.push(field); records.push(record); record = []; field = ""; i++; continue; }
    field += ch; i++;
  }
  if (field.length > 0 || record.length > 0) { record.push(field); records.push(record); }
  // drop fully empty trailing records
  while (records.length && records[records.length - 1].every((c) => c.trim() === "")) records.pop();
  return records;
}

export function normalizeHeader(h: string): string {
  return h.replace(/^﻿/, "").trim().toLowerCase().replace(/\s+/g, " ");
}

export function parseCsv(text: string, options: CsvOptions = {}): CsvResult {
  const delimiter = options.delimiter ?? detectDelimiter(text);
  const strategy = options.raggedRowStrategy ?? "error";
  const records = parseCsvRecords(text, delimiter);
  const headerRow = options.headerRow ?? 0;
  const headers = (records[headerRow] ?? []).map((h) => h.trim());
  const rows: CsvRow[] = [];
  const errors: CsvResult["errors"] = [];
  const width = headers.length;
  records.slice(headerRow + 1).forEach((raw, idx) => {
    if (raw.every((c) => c.trim() === "")) return;
    const warnings: string[] = [];
    let cells = raw;
    if (raw.length !== width) {
      if (strategy === "error") { errors.push({ index: idx, message: `expected ${width} columns, got ${raw.length}` }); return; }
      if (raw.length < width) { cells = [...raw, ...Array<string>(width - raw.length).fill("")]; warnings.push("padded_short_row"); }
      else if (strategy === "pad") { cells = raw.slice(0, width); warnings.push("truncated_long_row"); }
      else { cells = mergeOverflow(raw, headers, options.overflowColumn); warnings.push("merged_overflow_cells"); }
    }
    const obj: Record<string, string> = {};
    headers.forEach((h, i) => { obj[h] = (cells[i] ?? "").trim(); });
    rows.push({ index: idx, cells: obj, raw, warnings });
  });
  return { headers, rows, errors };
}

/** Fold extra cells into the "text" column (the longest cell) so that a comma in a synopsis does not shift the row. */
function mergeOverflow(raw: string[], headers: string[], overflowColumn?: string): string[] {
  const width = headers.length;
  const extra = raw.length - width;
  let target = overflowColumn ? headers.findIndex((h) => normalizeHeader(h) === normalizeHeader(overflowColumn)) : -1;
  if (target < 0) {
    // heuristic: the longest cell among the first `width` cells is the free-text one
    target = raw.slice(0, width).reduce((best, cell, i, arr) => (cell.length > arr[best].length ? i : best), 0);
  }
  const merged = raw.slice(0, target + 1).concat([]);
  merged[target] = raw.slice(target, target + extra + 1).join(",");
  return merged.concat(raw.slice(target + extra + 1));
}

export function detectDelimiter(text: string): string {
  const firstLine = text.split(/\r?\n/, 1)[0] ?? "";
  const counts: Array<[string, number]> = [",", ";", "\t", "|"].map((d) => [d, firstLine.split(d).length - 1]);
  counts.sort((a, b) => b[1] - a[1]);
  return counts[0][1] > 0 ? counts[0][0] : ",";
}
