/**
 * De-duplication across platforms and categories: the same submitter entering the same work
 * on FilmFreeway and FestHome (or in several categories) must become ONE film with several
 * submissions/entries. Mirrors normalize_title() in SQL.
 */

export function normalizeTitle(title: string | null | undefined): string {
  if (!title) return "";
  const stripped = title
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/^(the|a|an|le|la|les|der|die|das|el|los|las)\s+/, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
  return stripped;
}

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export interface DedupeCandidate {
  filmId: string;
  submitterEmail: string;
  normalizedTitle: string;
  runtimeSeconds: number | null;
}

export interface DedupeMatch {
  filmId: string;
  score: number; // 1 = exact, 0.85..0.99 = fuzzy
  reason: "exact_title" | "fuzzy_title";
}

/** Dice coefficient over character bigrams — cheap and good enough for titles; SQL side uses pg_trgm. */
export function similarity(a: string, b: string): number {
  if (a === b) return 1;
  if (a.length < 2 || b.length < 2) return 0;
  const grams = (s: string) => { const m = new Map<string, number>(); for (let i = 0; i < s.length - 1; i++) { const g = s.slice(i, i + 2); m.set(g, (m.get(g) ?? 0) + 1); } return m; };
  const ga = grams(a), gb = grams(b);
  let inter = 0;
  for (const [g, c] of ga) inter += Math.min(c, gb.get(g) ?? 0);
  return (2 * inter) / (a.length - 1 + b.length - 1);
}

export interface DedupeOptions {
  runtimeToleranceSeconds: number;
  fuzzyThreshold: number;
}

/**
 * Find existing films by the SAME submitter that are the same work.
 * Never matches across different submitter emails (a distributor and a director may both enter a film; that is a review case, not an auto-merge).
 */
export function findDuplicates(incoming: DedupeCandidate, existing: DedupeCandidate[], opts: DedupeOptions): DedupeMatch[] {
  const email = normalizeEmail(incoming.submitterEmail);
  const out: DedupeMatch[] = [];
  for (const e of existing) {
    if (normalizeEmail(e.submitterEmail) !== email) continue;
    if (incoming.runtimeSeconds !== null && e.runtimeSeconds !== null && Math.abs(incoming.runtimeSeconds - e.runtimeSeconds) > opts.runtimeToleranceSeconds) continue;
    if (e.normalizedTitle === incoming.normalizedTitle && incoming.normalizedTitle !== "") { out.push({ filmId: e.filmId, score: 1, reason: "exact_title" }); continue; }
    const s = similarity(incoming.normalizedTitle, e.normalizedTitle);
    if (s >= opts.fuzzyThreshold) out.push({ filmId: e.filmId, score: Math.round(s * 1000) / 1000, reason: "fuzzy_title" });
  }
  return out.sort((a, b) => b.score - a.score);
}

/** Exact matches auto-merge; fuzzy ones go to the dedup review queue. */
export function decideMerge(matches: DedupeMatch[]): { action: "merge"; filmId: string } | { action: "review"; filmId: string; score: number } | { action: "create" } {
  const exact = matches.find((m) => m.reason === "exact_title");
  if (exact) return { action: "merge", filmId: exact.filmId };
  if (matches[0]) return { action: "review", filmId: matches[0].filmId, score: matches[0].score };
  return { action: "create" };
}
