# DECISIONS_BUILD — deviations from O-02 and from the Build Brief

Every place where the platform build departs from `BGIFF_O-02_System_Blueprint_v1.1` or from the Build Brief v1, with the reason. The brief is an **engineering brief under revision**, not founder-approved; the founder decides everything marked *founder decision*.

Codes: `D-Bxx` = build decision · `C-1` = founder correction of 2026-09-30 (via advisors).

---

## Correction C-1 (2026-09-30) — applied

Received mid-session from the founder's advisors. It overrides brief §3.1, §3.4, §3.7 and §6 as follows. The affected migrations are marked **STATUS: DRAFT** in their header and remain draft until the founder confirms the model.

| # | Correction | Where it landed |
|---|---|---|
| C-1.1 | "Extra award consideration" is **not** the product. Each work chooses **one free primary category**; before initial screening the entrant may **pay** to have the **same work** considered in **additional eligible main categories** (of the 19). Craft/technical/identity/special honours are **separate products**, timing and pricing not final. Purchases never guarantee selection or awards. | `entries` = one row per (film, category) with `is_primary`, `status` (`pending_payment → active` on payment), `paid_order_id`. Screening (`screening_decisions.entry_id`), jury (`jury_assignments.entry_id`, `scores.entry_id`) and gates (`open_gate()`) read `entries`. Platform rows moved to a new `submissions` table. `categories.fit_rules` + `lib/platform/categories.ts` decide which categories may be offered. `products.kind ∈ {additional_category, honour_consideration, …}`; honour products seeded inactive with `metadata.status = not_final`. |
| C-1.2 | Three **separate acts**, never bundled or pre-ticked: (a) online-screening licence (L-03), (b) acceptance of the disclosed Gates rules (versioned text snapshot), (c) optional marketing consent (double opt-in). A licence alone is **not** acceptance of undisclosed rules. Gates mechanics stay off the public site; the entrant must **see and accept the rules privately in the dashboard** to count as accepted. | `consents.kind` check-constrained to `screening_licence | gates_rules | marketing`; `text_version` + `text_snapshot` copied by trigger from `consent_texts`; `films.screening_licence_at` and `films.gates_accepted_at` set **only** by the consents trigger (filmmaker column guard blocks direct writes); `submitters.marketing_status` follows `confirmed_at`. RLS: `consent_texts` with `kind = 'gates_rules'` readable only by logged-in submitters/staff, never by `anon`. `open_gate()` requires both film timestamps. Tested in `supabase/tests/rls.sql` and `gates.sql`. |
| C-1.3 | The brief is "under revision", not approved. Founder approval before any live change or entrant e-mail. | All docs reworded; every live switch is a `feature_flags` row, default off, `requires_founder = true`; the outbox send policy fails closed (`lib/platform/outbox.ts`). |
| C-1.4 | Update entry flow, dashboard flows, commerce, status model, automations, build plan. | Dashboard flow in `ARCHITECTURE.md §4.3`; `films.primary_category_confirmed_at`; automations seeded per kind (`consent_reminder_screening_licence`, `consent_reminder_gates_rules`, `marketing_double_optin`, `primary_category_confirm_reminder`); tickets B-05…B-09 and D-02 in `BUILD_PLAN.md`. |

**Migrations marked DRAFT because of C-1:** `20260930000300_intake_and_films.sql` (entries/consents/status parts), `20260930000400_screening_and_jury.sql` (entry-level scoping), `20260930000500_commerce.sql` (product catalogue). They apply and pass tests, but their shape may still change after the founder reviews the model. Shared infrastructure (auth, settings, flags, audit, outbox, intake, dedup, gates engine) is not draft.

---

## Build decisions

| Code | Decision | Deviates from | Reason |
|---|---|---|---|
| D-B01 | **Recommend a dedicated Supabase project `bgiff-platform` (Pro)**; migrations target the `public` schema. If the founder keeps the shared project instead, run the same files through `supabase/scripts/set-schema.sh bgiff` (renames the target schema; nothing else changes). | O-02 (shared project, `bgiff` schema) | Isolation from the live BIUFF/BIPA project (brief §1.9), independent backups/PITR, no shared connection limits at 30k films. *Founder decision.* |
| D-B02 | `submissions` (platform rows) and `entries` (film × category) are two tables. | O-02 `entries` (= platform rows) | C-1.1 needs a per-category row that has nothing to do with the intake channel. |
| D-B03 | No `wallet`, no per-card limit on votes; a sanity cap per checkout lives in `settings.gates.max_qty_per_checkout`. | — | Founder decision recorded in the brief; the cap only stops typos/bot bursts and is editable. |
| D-B04 | Votes are inserted **only** from the Stripe `payment_intent.succeeded` webhook, keyed by `stripe_event_id`. Late votes after a film is "through" are stored as `reversed` (and refunded by the app), not rejected, so reconciliation never loses money trails. | brief §3.5 wording ("refused") | Refusal happens at checkout time; a paid race must still be traceable. |
| D-B05 | Gate parameters are frozen once a gate is `closing`/`closed`; every change before that is versioned in `gate_config_versions`. | — | Auditability of the competition; brief asks for "versioned settings". |
| D-B06 | Sentry is wired via env vars and a ticket (A-11), **not** installed in this scaffold. | brief Phase A | `@sentry/nextjs` needs the DSN and a Vercel integration the founder must create; adding the SDK without config only adds bundle weight. |
| D-B07 | FilmFreeway / FestHome column presets are best-effort guesses, matched case-insensitively, editable rows in `import_mappings`; unmatched headers are reported per import run. | brief §7 ("real export from 27 Sep exists") | The two CSVs are on the founder's computer; the mapper is designed to be corrected in data, not code, once they are attached. |
| D-B08 | Roles are stored in `user_roles` and read via `current_roles()`; JWT mirroring by an auth hook is a ticket (A-04). | O-02 (JWT claims) | Works on day one without custom auth hooks; hook is an optimisation. |
| D-B09 | Staff writes go through the server with the service-role client **after** `decideAccess()`; RLS policies for staff roles exist as defence in depth. Column-level protection for filmmakers is done with `*_column_guard` triggers, not column grants. | O-02 (RLS only) | Column grants would also restrict admins on the `authenticated` role; triggers keep the RLS tests simple and explicit. |
| D-B10 | pgTAP is not used; RLS and gates tests are plain SQL `assert` blocks that run in CI against Postgres 16 with a small `auth` shim. | brief §10 ("RLS tests for each role") | No extra extension needed on Supabase or CI; same coverage. |
| D-B11 | Prices are stored **gross** (incl. VAT) with `vat_rate_bp`; net/VAT are derived per line, `net + vat = gross` always. | O-02 (net prices) | Consumer price display (PAngV) and Stripe Checkout both work in gross; avoids rounding drift on invoices. |
| D-B12 | Sequential numbers per year for orders, invoices and credit notes via `number_counters` (`INV-2026-000001`). Invoices are immutable (trigger + no-delete rule); corrections are credit notes. | — | §14 UStG / GoBD. |
| D-B13 | `audit_log` is append-only by rule (`ON UPDATE/DELETE DO INSTEAD NOTHING`) in addition to revoked grants, so even the service role cannot rewrite it. | O-02 (grants only) | Brief §1.8. |
| D-B14 | The public leaderboard view is `security_invoker`: anon only sees films that are `public_visible`. Films in gates are made public by the "online screening open" switch (Phase D). | — | Keeps the Gates model silent until launch (brief §1.3). |
| D-B15 | Branch: the session's designated branch is `claude/zealous-meitner-sv2ykz`; the brief asks for `platform/phase-a`. Both carry the same commits; the PR is opened from `platform/phase-a`. `main` untouched. | — | Satisfies both the harness rule and the founder's instruction. |
| D-B16 | The existing site pages, copy and `lib/data.ts` are untouched. New code lives in `lib/platform/**`, `lib/server/**`, `app/(platform)/**`, `app/api/platform/**`, `supabase/**`, `tests/**`, `docs/platform/**`. Only `package.json` (scripts/devDeps), `eslint.config.mjs`, `vitest.config.ts`, `.env.example`, `.github/workflows/ci.yml` and `README.md` (one section) were added or changed. | — | Brief task §3 ("do not change the live site pages"). |
| D-B17 | `contact.routing` setting sends hello@/submissions@/press@/partners@ to info@; the contact page itself is not edited in this PR. | brief §2 | Live page change needs founder "go". |
| D-B18 | Model names: `claude-fable-5-1` (drafts, Persian digest) and `claude-haiku-4-5-20251001` (classification) as **settings**, not constants. | — | Editable when prices/models change. |

## Open founder decisions (not build decisions)

See `FOUNDER_NEEDS.md`. Nothing in this PR requires them to be answered to merge; they gate the first deploy to staging.
