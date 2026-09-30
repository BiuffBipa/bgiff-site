# BGIFF Platform — Architecture (v1, Phase A)

Status: draft for founder review · 2026-09-30.
Inputs: `BGIFF_O-02_System_Blueprint_v1.1` (base spec, Persian, founder's folder) and the **Build Brief v1 — an engineering brief under revision, not founder-approved**. Correction C-1 (2026-09-30, via the founder's advisors) overrides the brief on categories, consents, commerce and the entrant status model. Every deviation from O-02 or the brief is listed in `DECISIONS_BUILD.md`. Prices, gate numbers, dates and the Supabase choice are open; founder approval is required before any live change or entrant e-mail.

---

## 1. Goals the architecture must serve

| Goal | Consequence |
|---|---|
| One source of truth | Postgres (Supabase). FilmFreeway / FestHome / CSV are *input channels* only. |
| Founder approves live changes | Every outward action (email send, price live, gate open, screening open) sits behind a **feature flag** stored in DB and defaults to *off*. |
| Gates model confidential until launch | No public page, email template or public API exposes gate/vote mechanics unless `flags.gates_public = true`. Consents are worded generically. |
| Never sell selection | Purchases write only to `orders` / `entitlements`. Gate progression reads only `votes`. Jury reads neither (RLS). |
| No dark patterns | Prices stored gross incl. VAT; no pre-ticked consents (consent rows exist only when granted). |
| AI proposes, humans approve | Agents write to `agent_proposals`; an admin action turns a proposal into a real change. Only FAQ auto-reply and explicitly enabled batch approvals bypass this. |
| 10× scale | Every hot table is keyed by UUID, indexed on the query paths in `SCHEMA.md`, and all background work is queue-based (`outbox`, `webhook_events`, `import_runs`, `jobs`). Nothing loops over films in a request handler. |
| Nothing hard-deleted | `deleted_at` on business tables + append-only `audit_log` (trigger-fed, revoke `UPDATE`/`DELETE`). |
| Don't touch BIUFF/BIPA | New, dedicated Supabase project (`bgiff-platform`). Nothing in this repo references `biuff-founding-2026`. |

---

## 2. Stack

| Layer | Choice | Why |
|---|---|---|
| Web / API | **Next.js 16 (App Router), React 19, TypeScript strict** | Already in repo; Vercel project `bgiff-site` exists. Public site, filmmaker dashboard, admin and API routes all live here as one app with route groups. |
| Hosting | **Vercel** (team BIPA, Pro) | Existing. `main` → production, every PR → preview. A protected `staging` branch gets a stable preview alias (`staging.bgiff.com`, DNS to be added by founder). |
| Database / Auth / Storage (small files) | **Supabase** — Postgres 16, RLS, Auth (magic link / OTP), Storage for posters/stills/subtitles | EU region (Frankfurt, `eu-central-1`). Dedicated project recommended (decision D-B01). |
| Large media | **Bunny.net** Storage (EU) + Stream | Film files (tus upload), encoding, signed playback. Phase B/D. |
| Payments | **Stripe** Checkout + Webhooks + Stripe Tax | Cards, Apple/Google Pay, PayPal (via Stripe where enabled). Phase D. |
| Email | **Resend** via `outbox` table + Resend webhooks | Transactional on `mail.bgiff.com`, marketing on `news.bgiff.com` (separate domains, separate reputation). |
| AI | **Anthropic API** (`claude-fable-5-1` for drafts/digest, `claude-haiku-4-5-20251001` for cheap classification) | All prompts + outputs persisted in `agent_runs`. |
| Jobs / cron | **Vercel Cron** → Next route handlers that drain queues in batches; plus **pg_cron** inside Supabase for DB-local jobs (gate closing check, retention). | No separate worker infra in v1. Every cron writes a `cron_runs` row (health). |
| Monitoring | Sentry (front + server), uptime ping on `/api/platform/health`, daily backup verification cron | Phase A ticket. |
| Analytics | Vercel Analytics (cookieless) + internal `events` table | No cookie banner needed for analytics. |
| CI | GitHub Actions: lint, typecheck, unit tests, migration up/down against Postgres 16 | See `.github/workflows/ci.yml`. |

Repository layout (after Phase A):

```
app/                      public site (existing, untouched) + new route groups
  (platform)/admin/       admin control centre (flag-gated)
  (platform)/my/          filmmaker dashboard (magic link)
  api/platform/           health, webhooks, cron entrypoints
lib/                      existing site data
lib/platform/             framework-free domain code (money, gates, access, intake, settings…)
supabase/migrations/      forward migrations (timestamped)
supabase/migrations/down/ matching reverse migrations
supabase/ci/              shims so migrations run on plain Postgres in CI
docs/platform/            this folder
tests/                    vitest unit tests + fixtures
```

Rule: `lib/platform/**` never imports Next.js, React or Supabase clients. It is pure TypeScript so it can be unit-tested and reused by cron handlers, route handlers and scripts.

---

## 3. Environments

| Env | Supabase | Vercel | Stripe | Resend | Flags |
|---|---|---|---|---|---|
| `local` | Supabase CLI (`supabase start`) or dedicated dev project | `next dev` | test keys | test API key, sandbox domain | all off |
| `staging` | **`bgiff-staging`** project (or `staging` schema if founder picks shared project) | preview alias `staging.bgiff.com` | test mode | `staging-mail.bgiff.com` | admin on, sends to allow-list only |
| `production` | **`bgiff-platform`** project (Frankfurt) | `bgiff.com` | live mode | `mail.bgiff.com`, `news.bgiff.com` | each live switch flipped only after founder "go" |

Seeded test data (the two 27 Sep CSV exports) goes to **staging only**. Production intake starts from the FilmFreeway API backfill.

Secrets live in Vercel env vars and Supabase Vault, never in the repo. `.env.example` lists every variable.

---

## 4. Services and data flow

```
FilmFreeway API/webhook ─┐
FestHome webhook ────────┼─▶ webhook_events (idempotent, raw JSON) ─▶ intake worker ─▶ import_runs
CSV upload (admin) ──────┘        │                                        │
                                  │                     mapper (import_mappings preset)
                                  ▼                                        ▼
                         dedup queue (dedup_candidates) ◀── submitters / people / films / entries / film_assets
                                                                 │
                    AI pre-check (agent_runs → screening_flags)  │
                    human screening (screening_decisions) ◀──────┘
                                  │ eligible
                                  ▼
             outbox ──▶ Resend ──▶ email_events   "your film page is ready" (flag-gated)
                                  │
                                  ▼
                 filmmaker dashboard (magic link) : consents, category, uploads (Bunny), withdraw, orders
                                  │
                                  ▼
                 Gates engine : gates → gate_films → votes (from Stripe payment_intent.succeeded only)
                                  │ capacity / time-window close → laurels
                                  ▼
                 Jury module (blind: RLS hides votes/orders) → scores → results sign-off → honours
```

### 4.1 Intake

1. Every inbound payload (webhook or CSV row batch) is stored **raw** in `webhook_events` (`source`, `external_id`, `signature_ok`, `payload jsonb`) with a unique `(source, external_id)` key → idempotent.
2. A cron (`/api/platform/cron/intake`) picks unprocessed events in batches of 200, runs the mapper for that `source`, and upserts `submitters` → `people` → `films` → `entries` → `film_assets`. Each batch is an `import_runs` row with counters and per-row errors (`import_errors`).
3. Mapping is data, not code: `import_mappings` holds one preset per platform (FilmFreeway, FestHome, Sfilmmaker, … ), each a JSON list of `{ target, sourceHeaders[], transform }`. Admin can edit a preset and re-run a failed import. The TypeScript mapper (`lib/platform/intake/mapper.ts`) only interprets this JSON.
4. CSV parsing is RFC-4180-tolerant (`lib/platform/intake/csv.ts`): quoted commas, embedded newlines, BOM, CRLF, ragged rows. FestHome's broken commas are handled by a `ragged_row_strategy` on the preset.
5. Dedup key = `submitter_key + normalised_title` (lowercase, strip punctuation/articles/diacritics) with runtime tolerance ±2 min. Exact hits auto-merge into one `film` with several `entries`; fuzzy hits go to `dedup_candidates` for admin review. Never auto-merges across different submitter emails.
6. Bulk submitters: a nightly job sets `submitters.kind = 'distributor'` when `count(films) ≥ settings.intake.distributor_threshold` (default 10). Distributors are excluded from filmmaker-facing automations.

### 4.2 Screening

- AI pre-check agent reads a film + assets and writes `screening_flags` (`kind`: format, runtime, subtitles, duplicate, category_fit, ai_declaration, other; `severity`; `note`). It never writes a decision.
- Screeners see a queue filtered by assignment (`screening_assignments`) and record `screening_decisions` (`eligible | ineligible | needs_info`, reason, internal note). Latest decision wins; history kept. [C-1] A decision is about the work (`entry_id` null) or about one category entry (`entry_id` set: category fit). Screening and jury read `entries`, never a single category on `films`.
- [C-1] Paid additional categories must be bought **before initial screening**; the dashboard hides the "add category" option once the film leaves `precheck`/`imported`.
- `films.status` is a derived state machine: `imported → precheck → in_screening → eligible | ineligible | needs_info → in_gates → jury → honoured | eliminated | withdrawn`. Transitions go through one function `transitionFilm()` that writes `film_status_events` and the audit log.

### 4.3 Filmmaker dashboard and auth

- No passwords, no sign-up. A submitter requests a link with the email that was on their submission. `magic_link_tokens` stores `sha256(token)`, `expires_at` (15 min), `used_at`, `user_agent_hash`, `ip_hash`. A token is single-use; consuming it creates a Supabase Auth session bound to `submitters.id` (via `auth_user_id`).
- Everything the filmmaker sees is scoped by RLS to rows where `submitter_id = current_submitter()`.
- [C-1] Three **separate acts**, never bundled, never pre-ticked, each its own row in `consents` with `kind ∈ {screening_licence, gates_rules, marketing}`, `text_version` and a frozen `text_snapshot` of exactly what the person saw, plus `source`, `ip_hash`, timestamp. No consent row = no consent.
  - `screening_licence` (L-03) per film → stamps `films.screening_licence_at` (trigger; the app cannot set it directly).
  - `gates_rules` per film → the entrant must **see and accept the disclosed Gates rules privately in the dashboard**; stamps `films.gates_accepted_at`. The rules text (`consent_texts.kind = 'gates_rules'`) is readable only behind login (RLS) while the public site stays silent. A licence alone is **not** acceptance of undisclosed rules.
  - `marketing` per submitter → double opt-in (`confirmed_at`), drives `submitters.marketing_status`.
- [C-1] Category flow in the dashboard: confirm the free primary category (`films.primary_category_confirmed_at`), optionally add further **fitting** main categories (`categories.fit_rules`, `lib/platform/categories.ts`) as `entries.status = 'pending_payment'`; the entry becomes `active` only when its order is paid (`entries.paid_order_id`). Purchases never guarantee selection or an award, and the UI says so.
- Uploads: dashboard asks the API for a signed Bunny tus upload URL (`upload_sessions`), Bunny webhook marks `film_assets.status = ready`.

### 4.4 Gates engine (design)

Everything below is driven by rows in `gates` and by `settings`, never by constants. Pure logic lives in `lib/platform/gates/engine.ts` and is unit-tested.

**Entities**

- `gates`: `n`, `name`, `threshold` (votes a film needs to be "through"), `capacity` (max films that pass), `vote_price_cents`, `booking_fee_cents`, `opens_at`, `closes_at`, `status` (`draft | scheduled | open | closing | closed`), `config_version`, `parent_gate_id`.
- `gate_films`: one row per eligible film per gate: `votes` (materialised counter), `status` (`active | through | eliminated | withdrawn`), `through_at`, `rank_at_close`.
- `votes`: one row per **paid, succeeded** purchase line: `gate_id`, `film_id`, `order_id`, `qty`, `buyer_email_hash`, `country`, `status` (`counted | reversed`), `reversed_reason`.

**Eligibility for gate 1** ([C-1]): `films.status = 'eligible'` ∧ primary entry in an online-screening category ∧ `screening_licence_at` set ∧ `gates_accepted_at` set. Enforced in `open_gate()`.

**Rules**

1. A vote row is inserted **only** by the Stripe webhook handler after `payment_intent.succeeded`, keyed by `stripe_event_id` (unique) → idempotent. The insert trigger increments `gate_films.votes` atomically (`UPDATE … SET votes = votes + qty WHERE status = 'active'`).
2. If the film has already reached `threshold` in this gate, the purchase is refused at checkout time **before** payment (server checks `gate_films.status = 'active'`). A race that still lands after the film is through is refunded automatically and the vote row marked `reversed`.
3. When `gate_films.votes ≥ gates.threshold` the trigger sets `status = 'through'`, `through_at = now()`, and the film stops accepting votes for this gate.
4. A gate closes when `count(through) ≥ capacity` **or** `now() ≥ closes_at`. Closing is done by one idempotent function `close_gate(gate_id)` (pg function, called by pg_cron every minute while a gate is `open`, or by admin): remaining slots (`capacity − through`) go to the highest-voted `active` films (tie-break: earliest last vote, then earliest submission); everyone else becomes `eliminated`; laurels `gate_n` are issued to eliminated films; the next gate's `gate_films` rows are created with `votes = 0` for the films that passed.
5. Refund / chargeback (`charge.refunded`, `charge.dispute.created`) reverses the vote rows of that order (`status = 'reversed'`) and decrements the counter. If the film had already passed and the gate is still open, it drops back to `active` if it falls under threshold; after close, nothing changes automatically — a fraud alert is raised for admin review with an audit reason.
6. Prices are per gate (`vote_price_cents`, `booking_fee_cents`) and versioned: changing them creates a new `gate_config_versions` row; orders store the price they paid.
7. Rate-limiting and bot protection sit at the checkout API (per IP / per email hash sliding window in `rate_limits`), never on the vote itself. Turnstile is switched on per gate via `gates.captcha_mode` only when the fraud monitor flags abuse.
8. Manual overrides (`gate_films.status` change by admin) require a reason and are written to `audit_log` with `actor`, `reason`, before/after.

**Observability**: `gate_leaderboard` is a view (`gate_films` joined to `films`, ordered by votes) with a materialised variant refreshed every 30 s while a gate is open. The jury role has no grant on any of these objects.

### 4.5 Commerce

- [C-1] Three product families, kept apart in `products.kind`: **`additional_category`** (the same work considered in another main category, bought before screening; the paid `entries` row is the entitlement), **`honour_consideration`** (craft/technical, identity/thematic, special — separate products whose timing and pricing are **not final**), and services (`laurel_print`, `feedback`, `promo`, `table_read`, `b2b_package`, `ticket`). Votes are `vote`.
- `prices` (gross cents, currency, VAT rate, valid window, gate_id for votes), `coupons`, `orders` + `order_lines` (snapshot of price, VAT, product, `entry_id` for additional categories), `invoices` (sequential number from `number_counters`, immutable, PDF), `refunds`, `entitlements` (what a film/submitter now has, e.g. `honour_consideration:craft`).
- VAT: German 19 % default; EU B2B reverse charge when a valid VAT ID is supplied (Stripe Tax validates); OSS threshold monitor is a report over `order_lines` grouped by buyer country.
- Entitlements never feed screening, gates or jury logic. A DB `CHECK`/policy prevents any `screening_*`, `gate_*`, `scores` table from referencing `orders`.

### 4.6 Jury

- `jurors` (linked to `auth_user_id`, role `juror`), `jury_assignments`, `scores` (rubric JSON, versioned), `conflicts` (declared per film), `results` (final honours, signed off by founder with audit row).
- Blind mode = RLS. The `juror` role has `SELECT` on `films`, `film_assets` (screener only), `jury_assignments`, its own `scores`; **no** grant on `votes`, `gate_films`, `orders`, `entitlements`, `submitters.email`.

### 4.7 Marketing, CRM and email

- [C-1] Consent reminders are **per kind** (`consent_reminder_screening_licence`, `consent_reminder_gates_rules`, `marketing_double_optin`, plus `primary_category_confirm_reminder`); no automation bundles the three acts.
- All email goes through `outbox` (`to`, `template_key`, `variables`, `kind` `transactional|marketing`, `scheduled_for`, `status`, `provider_message_id`). A cron drains it in batches (Resend batch API), respecting `suppressions` (bounces, complaints, unsubscribes) and `settings.email.send_allowlist` on non-production.
- Resend webhooks → `email_events` (delivered, opened, clicked, bounced, complained). Per-recipient timeline = union of `outbox`, `email_events`, `crm_activities`.
- Marketing lists require double opt-in (`consents.kind = 'newsletter'` + `confirmed_at`). Transactional templates carry no sales copy.
- `segments` are saved filters (JSON DSL evaluated server-side); `campaigns` reference a segment + template + schedule; `campaign_sends` is one row per recipient (idempotent). `automations` are rule rows (`trigger_event`, `delay`, `template`) executed by the event bus (`events` table).
- Distributors (`submitters.kind = 'distributor'`) are excluded from every filmmaker automation by a segment guard.

### 4.8 AI agents

- Each run is an `agent_runs` row: `agent`, `model`, `input_ref`, `prompt`, `output`, `tokens`, `cost_cents`, `status`. Outputs that change state become `agent_proposals` (`kind`, `target`, `payload`, `status: proposed|approved|rejected`, `decided_by`).
- Agents in v1: `precheck` (screening flags), `email_draft`, `founder_digest` (daily, Persian), `faq_reply` (auto-send allowed if `flags.faq_autoreply`), `critique_draft` (paid add-on, expert-approved).

---

## 5. Roles and access

Roles are stored in `user_roles` (`auth_user_id`, `role`) and mirrored into the JWT via a Supabase Auth hook (`app_metadata.roles`). Public site readers have no session.

| Role | Sees | Does |
|---|---|---|
| `founder` | everything | everything, incl. sign-off and flag switches |
| `admin` | everything except finance payouts and flag switches | run intake, screening, gates, marketing, content |
| `screener` | screening queue, films assigned, assets | decisions on assigned films |
| `programmer` | eligible films, programme, event | build programme |
| `juror` | assigned films (blind) | scores, conflicts |
| `support` | submitters, films (read), outbox, crm | notes, tasks, reply templates |
| `finance` | orders, invoices, refunds, payouts, reports | refunds, invoice corrections (credit notes) |
| `filmmaker` | own submitter row, own films, own orders/invoices/consents/laurels | dashboard actions |
| `distributor` | same as filmmaker for all its films + B2B catalogue | bulk consents, B2B orders |
| `public` | published films, programme, leaderboard (when live) | buy votes (no account) |

One TypeScript entrypoint `decideAccess(actor, action, resource)` (`lib/platform/access.ts`) encodes the same matrix as the RLS policies and is used in route handlers before any query, so the app never relies on RLS alone for UX, and RLS never relies on the app for safety. RLS tests per role are a Phase A ticket (`supabase/tests/rls.sql`, pgTAP).

---

## 6. Integrations (contracts)

| Integration | Direction | Auth / verification | Idempotency | Fallback |
|---|---|---|---|---|
| FilmFreeway API | pull (backfill + hourly sync) | read-only API key (Vault) | `external_id = submission_id` | CSV upload with `filmfreeway` mapping preset |
| FilmFreeway webhooks | push | shared secret header + HMAC (per their docs) | `webhook_events(source,external_id)` | hourly pull |
| FestHome webhook | push (JSON per submission) | secret token in URL/header | same | CSV/XLSX export with `festhome` preset |
| Other platforms | CSV | n/a | file hash + row index | n/a |
| Stripe | push | signature header, `STRIPE_WEBHOOK_SECRET` | `stripe_event_id` unique | Stripe events replay |
| Resend | push (email events) | Svix signature | `provider_event_id` unique | daily reconciliation pull |
| Bunny | push (encode finished) | shared token | `asset_id + status` | manual re-check |
| Anthropic | pull | API key | `agent_runs.id` | n/a |

All webhook endpoints: verify signature → insert raw event (return 200 even if processing later fails) → processing cron. Never process synchronously inside the webhook request.

---

## 7. Security and compliance mapping

| Requirement | Implementation |
|---|---|
| RLS on every table | `20260930001000_rls.sql`; `ALTER TABLE … ENABLE ROW LEVEL SECURITY` + `FORCE`; default deny; service role only from server. |
| Jury cannot see votes/orders | no policy for `juror` on those tables; `gate_leaderboard` view has `security_invoker`. |
| Filmmakers see only their rows | policies use `current_submitter_id()` helper. |
| Magic links | 15 min, single-use, hashed token, UA/IP hash, rate-limited (5 / 15 min / email). |
| Webhook signature + idempotency | see §6. |
| PII minimisation | `votes.buyer_email_hash` only; raw buyer email lives on `orders` (needed for receipt) with retention job per R-06. |
| Retention | `retention_policies` table + monthly pg_cron job that anonymises (never deletes) rows past their window. |
| Legal pages | content in `site_pages` with placeholders `{{legal.operator}}` etc. filled from `settings.legal.*`. |
| Invoices | sequential per year (`invoice_counters`), immutable after issue, credit notes for corrections, 19 % VAT, reverse charge flag, OSS report. |
| Consent snapshots | `consent_texts(version, locale, body_md)`; `consents.consent_text_id`. |
| Audit | trigger on all business tables → `audit_log` (append-only, `REVOKE UPDATE, DELETE`). |

---

## 8. Performance and scale notes

- Films list for admin: keyset pagination on `(created_at, id)`; full-text search via `films.search_tsv` GIN index.
- Vote counter is materialised on `gate_films` (one row update per purchase), leaderboard reads never aggregate `votes`.
- Outbox drain: 500 rows / minute per cron tick; back-pressure via `attempts` and exponential `next_attempt_at`.
- Import: 1,000 rows per `import_runs` batch; a 30k-film CSV = 30 runs, each < 30 s on a Vercel function.
- Target budgets: dashboard p95 < 1.5 s, API p95 < 300 ms, measured via Vercel Speed Insights + Sentry performance.

---

## 9. Open items handed to the founder

See `FOUNDER_NEEDS.md`. Nothing in this document requires a decision from the founder except the Supabase project choice (D-B01) — the schema and code are the same in both options.
