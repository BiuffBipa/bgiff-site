/**
 * [C-1] Category fit rules. A work has ONE free primary category (entries.is_primary) and may PAY,
 * before initial screening, to be considered in additional main categories that fit it.
 * `fit_rules` come from the `categories` table (editable), e.g.
 *   {"work_kind":"film","min_runtime_seconds":2400}                 feature
 *   {"work_kind":"film","max_runtime_seconds":2399}                 short
 *   {"work_kind":"film","requires":["is_student"]}                  student
 */
export type WorkKind = "film" | "screenplay" | "photography";

export interface FitRules {
  work_kind?: WorkKind;
  min_runtime_seconds?: number | null;
  max_runtime_seconds?: number | null;
  /** boolean flags on the film that must be true (is_student, is_first_film, ai_used…) */
  requires?: string[];
}

export interface CategoryRow {
  key: string;
  name: string;
  work_kind: WorkKind;
  online_screening: boolean;
  active: boolean;
  fit_rules: FitRules;
}

export interface FilmFacts {
  work_kind: WorkKind;
  runtime_seconds: number | null;
  is_student?: boolean | null;
  is_first_film?: boolean | null;
  ai_used?: boolean | null;
  [flag: string]: unknown;
}

export interface FitResult {
  category: CategoryRow;
  fits: boolean;
  reasons: string[];
}

export function checkFit(category: CategoryRow, film: FilmFacts): FitResult {
  const r = category.fit_rules ?? {};
  const reasons: string[] = [];
  if (!category.active) reasons.push("category_inactive");
  if (r.work_kind && r.work_kind !== film.work_kind) reasons.push(`work_kind_${r.work_kind}_required`);
  if (typeof r.min_runtime_seconds === "number") {
    if (film.runtime_seconds === null) reasons.push("runtime_unknown");
    else if (film.runtime_seconds < r.min_runtime_seconds) reasons.push("runtime_too_short");
  }
  if (typeof r.max_runtime_seconds === "number") {
    if (film.runtime_seconds === null) reasons.push("runtime_unknown");
    else if (film.runtime_seconds > r.max_runtime_seconds) reasons.push("runtime_too_long");
  }
  for (const flag of r.requires ?? []) {
    if (film[flag] !== true) reasons.push(`requires_${flag}`);
  }
  return { category, fits: reasons.length === 0, reasons: [...new Set(reasons)] };
}

/** Categories the dashboard may OFFER as paid additional categories: fitting, active, and not already entered. */
export function eligibleAdditionalCategories(categories: CategoryRow[], film: FilmFacts, alreadyEntered: readonly string[]): FitResult[] {
  return categories
    .filter((c) => !alreadyEntered.includes(c.key))
    .map((c) => checkFit(c, film))
    .filter((f) => f.fits);
}

/** Resolve a platform category name to a category key using the aliases column (case/space-insensitive). */
export function resolveCategoryAlias(raw: string | null | undefined, categories: Array<{ key: string; name: string; aliases: string[] }>): string | null {
  if (!raw) return null;
  const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9+]+/g, " ").trim();
  const target = norm(raw);
  for (const c of categories) {
    if (norm(c.name) === target) return c.key;
    if (c.aliases.some((a) => norm(a) === target)) return c.key;
  }
  return null;
}
