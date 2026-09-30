# BUILD_PLAN — Phases A–F as tickets

Estimates are engineering days for one engineer + Claude Code. "AC" = acceptance criteria. Every phase ends with a Persian report (§12 of the brief). Tickets marked **[C-1]** implement Correction C-1; tickets marked **[founder]** cannot start before the founder's input in `FOUNDER_NEEDS.md`.

Status legend: ✅ done in this PR · 🟡 partly · ⬜ open.

---

## Phase A — Foundation (weeks 1–2)

| # | Ticket | Est. | Status | AC |
|---|---|---|---|---|
| A-01 | Schema migrations (10 files) + reverse migrations + CI check | 3d | ✅ | `npm run db:check` applies up → tests → down → up on Postgres 16 with zero tables left; every migration has a `down/` file. |
| A-02 | RLS on every table, default deny, role policies | 2d | ✅ | `supabase/tests/rls.sql` passes for anon, juror (blind), filmmaker, screener, finance, admin. |
| A-03 | Gates engine in SQL (`open_gate`, `close_gate`, vote triggers) + TS mirror + tests | 2d | ✅ | `supabase/tests/gates.sql` + `tests/unit/gates.test.ts` pass: threshold, capacity, time close, tie-break, refund, post-close alert, votes reset. |
| A-04 | Auth: magic-link issue/verify routes, Supabase Auth session, roles → JWT hook | 2d | 🟡 lib done | `/auth/request` + `/auth/magic` routes; token single-use, 15 min (setting), rate-limited via `rate_limit_hit()`; `current_roles()` served from JWT claim with DB fallback. |
| A-05 | Settings & feature-flag admin (read/write with audit reason) | 1d | 🟡 registry done | Admin can edit any `settings` row; history visible; flags flip only by founder role. |
| A-06 | Outbox drain cron + Resend adapter + webhook → `email_events` | 2d | 🟡 policy done | Cron sends ≤ `email.batch_size` rows/min; send policy tests pass; non-prod allowlist enforced; Svix signature verified. |
| A-07 | Dedicated Supabase project, staging env on Vercel, env vars, `staging.bgiff.com` | 0.5d | ⬜ [founder] | Health route returns `database: ok` on staging; no secrets in repo. |
| A-08 | Seed staging with the two 27 Sep CSVs through the mapper (`scripts/import-csv.ts`) | 1d | ⬜ [founder: CSVs] | ~1,900 films visible; unmatched headers reported; dedup queue populated; presets corrected in `import_mappings`. |
| A-09 | Admin shell: layout, nav, films table (keyset pagination, search, filters, CSV export), film dossier read-only | 3d | 🟡 placeholder | Admin (flag `admin_enabled`) browses films at p95 < 1.5 s with 30k rows. |
| A-10 | CI: lint, typecheck, unit tests, migration check on PRs | 0.5d | ✅ | `.github/workflows/ci.yml` green. |
| A-11 | Sentry (client+server), uptime ping on `/api/platform/health`, daily backup-verification cron | 1d | ⬜ [founder: DSN] | Errors appear in Sentry; `cron_runs` shows a daily `backup_check` success. |
| A-12 | Persian one-pager: "how to read the admin films table" | 0.5d | ⬜ | Exists in `docs/platform/fa/`. |

**Deliverable:** staging URL, schema docs (✅), ~1,900 entries in staging, admin browses films.

## Phase B — Intake, Dossier, Dashboard (weeks 2–4)

| # | Ticket | Est. | Status | AC |
|---|---|---|---|---|
| B-01 | FilmFreeway API backfill + hourly sync + webhook endpoint (`webhook_events`) | 2d | ⬜ [founder: key] | Every submission has a `submissions` row; re-runs are idempotent. |
| B-02 | FestHome webhook + CSV/XLSX preset with `merge-overflow` | 1d | ⬜ | Broken-comma rows import without column shift (unit test exists). |
| B-03 | Generic CSV import UI with preset picker, header preview, unmatched-column report, re-run | 2d | ⬜ | Admin imports any platform CSV; errors listed per row. |
| B-04 | Dedup queue UI (merge / keep separate) + nightly distributor tagging | 1.5d | ⬜ | `dedup_candidates` reviewed; `submitters.kind = distributor` for ≥ threshold. |
| B-05 | **[C-1]** Dashboard: film list, status, primary-category confirmation (`primary_category_confirmed_at`) | 2d | ⬜ | Entrant sees only own films; confirms one primary category; change blocked after confirmation unless flag. |
| B-06 | **[C-1]** Dashboard: three separate consent screens — licence (L-03), Gates rules (private text, must scroll/see before tick), marketing (double opt-in mail) | 2d | ⬜ [founder: texts] | Three independent `consents` rows with snapshots; no pre-ticked boxes; `gates_accepted_at` stamped by trigger only; rules text 404 for anon. |
| B-07 | **[C-1]** Dashboard: "add category" picker limited by `fit_rules`, creates `entries(pending_payment)`; hidden after screening starts | 1.5d | ⬜ | Only fitting categories offered; UI states "no guarantee of selection or award". |
| B-08 | Uploads: Bunny signed tus URLs, `upload_sessions`, encode webhook → `film_assets` | 2d | ⬜ [founder: keys] | 20 GB file uploads resume; asset becomes `ready`. |
| B-09 | Withdraw flow + credits editing + invoices list | 1d | ⬜ | `withdrawn_at` set with reason; audit row written. |
| B-10 | Admin dossier (full): assets, credits, timeline, notes, tags, emails sent, orders, consents | 2d | ⬜ | Every table joined to a film is visible on one page. |
| B-11 | Notification templates (`film_ready`, per-kind consent reminders) as **drafts**; test-list send only | 1d | ⬜ [founder: go] | `emails_enabled` off → rows stay `queued`; allowlist send works on staging. |

**Deliverable:** founder can send "your film page is ready" to a test list.

## Phase C — Screening, CRM, Marketing (weeks 4–6)

| # | Ticket | Est. | Status | AC |
|---|---|---|---|---|
| C-01 | AI pre-check agent → `screening_flags` (+ `agent_runs`, `agent_proposals`) | 2d | ⬜ | Flags for format/runtime/subtitles/duplicate/category-fit/AI-declaration; no decision written by AI. |
| C-02 | Screening queue, assignments, decisions per film **and per entry [C-1]**, batch approve (flag) | 2.5d | ⬜ | Screener sees only assigned films; decision history kept; `films.status` transitions logged. |
| C-03 | CRM: submitter 360, activities, tasks, segments (DSL), saved views | 2.5d | ⬜ | Segment "Iran + eligible + no gates_rules consent" resolves in < 300 ms. |
| C-04 | Campaigns (template, A/B subject, schedule) + automations runner over `events` | 2d | ⬜ | Distributors excluded by segment guard; per-recipient timeline. |
| C-05 | Deliverability: bounces/complaints → `suppressions`, unsubscribe link, double opt-in confirm route | 1d | ⬜ | Suppressed recipients never receive marketing. |
| C-06 | Daily founder digest (Persian, AI) + weekly export | 1d | ⬜ | Digest row in `agent_runs`; sent to founder only. |

## Phase D — Commerce & Gates (weeks 6–9)

| # | Ticket | Est. | Status | AC |
|---|---|---|---|---|
| D-01 | Products/prices/coupons admin; Stripe catalogue sync (test mode) | 1.5d | ⬜ [founder: prices] | No hard-coded price anywhere (grep-guard in CI). |
| D-02 | **[C-1]** Additional-category checkout → order paid → `entries.status = active`, `paid_order_id` set; honour-consideration products stay inactive until founder sets timing | 1.5d | ⬜ | Webhook idempotent; refund reverts entry to `pending_payment`/`withdrawn` with audit. |
| D-03 | Vote checkout (no account): quote, rate limit, Stripe Checkout (cards/Apple/Google Pay/PayPal), webhook → `votes` | 2.5d | ⬜ | `quoteVotes()` totals match Stripe; late vote refunded automatically. |
| D-04 | Invoices (PDF, sequential, VAT, reverse charge), credit notes, refunds UI, Stripe reconciliation, OSS monitor | 2.5d | ⬜ | Invoice immutable; OSS report by buyer country. |
| D-05 | Gates admin: configure, schedule, open, live leaderboard, close/extend, manual override with reason, fraud alerts | 2.5d | ⬜ | pg_cron calls `close_due_gates()` every minute; overrides audited. |
| D-06 | Online screening pages (Bunny Stream signed playback, geo restrictions), film pages, category pages, leaderboard pages (flag `gates_public`) | 3d | ⬜ | Player only when `online_screening_open`; leaderboard 404 while flag off. |
| D-07 | Laurel generator (digital, free) for gate/selection/honours | 1d | ⬜ | PNG/SVG downloadable from dashboard. |
| D-08 | Fraud dashboard (velocity, same buyer many films, geo anomalies) + `captcha_mode` per gate | 1.5d | ⬜ | Alerts open/dismiss/action; Turnstile only when enabled. |

**Deliverable:** Gate 1 end-to-end on staging with Stripe test payments.

## Phase E — Jury, Results, Event (weeks 9–11)

| # | Ticket | Est. | Status | AC |
|---|---|---|---|---|
| E-01 | Jury module: jurors, assignments per entry [C-1], rubric, conflicts, blind mode | 3d | ⬜ | RLS test proves jurors never see votes/orders. |
| E-02 | Rankings + results sign-off (founder) + publication switch | 1.5d | ⬜ | `results.public_at` gates public pages. |
| E-03 | Certificates/laurels for honours; printed-laurel order flow | 1d | ⬜ | Free digital always; print is a product. |
| E-04 | Programme & venue admin → public programme page; tickets (later) | 1.5d | ⬜ | Published items only. |
| E-05 | Press page, partners page, FAQ from DB | 1d | ⬜ | Content editable in admin. |

## Phase F — Hardening & Launch

| # | Ticket | Est. | Status | AC |
|---|---|---|---|---|
| F-01 | Load test: 30k films, 100k votes, leaderboard under load | 1.5d | ⬜ | API p95 < 300 ms, dashboard p95 < 1.5 s. |
| F-02 | Security review: webhooks, rate limits, RLS diff vs `decideAccess()`, secrets scan | 1.5d | ⬜ | Findings closed or accepted by founder. |
| F-03 | Legal pages from settings (Impressum, Privacy, AGB, Withdrawal, Cookies) [founder: USt-IdNr] | 1d | ⬜ | Real operator data; no placeholders. |
| F-04 | Backups/restore drill, retention job, runbooks, on-call notes | 1d | ⬜ | Restore into a scratch project verified. |
| F-05 | German `/de` via next-intl (phase 2 content) | 2d | ⬜ | Flag `locale_de`. |
| F-06 | Founder training (Persian one-pagers per module, short GIFs) + launch checklist with a "go" per switch | 1d | ⬜ | Every flag flip has a checklist line. |

---

## Definition of done reminders (brief §10)

TypeScript strict · ESLint clean · unit tests for money/votes/gates · integration tests for webhooks · Playwright e2e for dashboard, checkout, admin critical paths · every migration reversible · RLS tests per role · no secrets in repo · `.env.example` complete · Persian one-pager per module.
