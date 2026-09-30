# supabase/

- `migrations/` — forward migrations, timestamped, applied in order by the Supabase CLI (`supabase db push`) or `psql`.
- `migrations/down/` — one reverse file per migration; CI proves up → down → up.
- `tests/rls.sql`, `tests/gates.sql` — behaviour tests (plain SQL assertions) run by `scripts/check-migrations.sh`.
- `ci/00_supabase_shim.sql` — emulates `auth.uid()/jwt()/role()` and the `anon/authenticated/service_role` roles on plain Postgres. **Never run on a real Supabase project.**
- `scripts/check-migrations.sh` — `npm run db:check`.
- `scripts/gen-schema-doc.sh` — regenerates `docs/platform/SCHEMA.md`.
- `scripts/set-schema.sh` — rewrites the migrations to target another schema (shared-project option, decision D-B01).

Production notes: enable `pg_cron` in the dashboard and schedule `select close_due_gates();` every minute while gates run, `select tag_distributors();` nightly, and the retention job monthly (Phase A-11 / F-04).
