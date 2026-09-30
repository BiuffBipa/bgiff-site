# BGIFF Platform docs

| File | What |
|---|---|
| `ARCHITECTURE.md` | Stack, environments, data flow, Gates engine design, roles/RLS, integrations, security mapping |
| `SCHEMA.md` | **Generated** from the migrations: every table, column, key, index, trigger and RLS policy |
| `BUILD_PLAN.md` | Phases A–F as tickets with estimates, status and acceptance criteria |
| `DECISIONS_BUILD.md` | Every deviation from O-02 / the brief, and Correction C-1 |
| `FOUNDER_NEEDS.md` | (Persian) the exact list of decisions, keys and documents needed from the founder |

Code map: `lib/platform/**` (pure domain code, unit-tested) · `lib/server/**` (Supabase clients) · `supabase/migrations/**` (+ `down/`) · `supabase/tests/*.sql` (RLS + gates behaviour) · `supabase/scripts/*` (migration check, schema doc generator, schema rename) · `tests/unit/**`.

Local checks: `npm run lint && npm run typecheck && npm test && npm run db:check` (the last needs a local Postgres 16 reachable via `PGHOST/PGPORT/PGUSER` or `DATABASE_URL`).
