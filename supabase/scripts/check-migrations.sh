#!/usr/bin/env bash
# Applies every forward migration in order on a fresh database, then applies every
# down migration in reverse order, then applies forward again (proves reversibility).
# Usage: DATABASE_URL=postgres://... supabase/scripts/check-migrations.sh
#   or:  PGHOST/PGPORT/PGUSER set, DBNAME defaults to bgiff_ci
set -euo pipefail
cd "$(dirname "$0")/../.."

DBNAME="${DBNAME:-bgiff_ci}"
export PGOPTIONS='-c client_min_messages=warning'
PSQL=(psql -v ON_ERROR_STOP=1 -q -o /dev/null -X)
if [[ -n "${DATABASE_URL:-}" ]]; then
  ADMIN_URL="${DATABASE_URL%/*}/postgres"
  psql -X -v ON_ERROR_STOP=1 -q "$ADMIN_URL" -c "drop database if exists $DBNAME" -c "create database $DBNAME"
  TARGET=("${DATABASE_URL%/*}/$DBNAME")
else
  psql -X -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $DBNAME" -c "create database $DBNAME"
  TARGET=(-d "$DBNAME")
fi

run() { "${PSQL[@]}" "${TARGET[@]}" -f "$1" 2> >(grep -v '^psql:.*NOTICE' >&2 || true); }

echo "== shim"; run supabase/ci/00_supabase_shim.sql
UP=$(ls supabase/migrations/*.sql | sort)
for f in $UP; do
  d="supabase/migrations/down/$(basename "${f%.sql}").down.sql"
  [[ -f "$d" ]] || { echo "missing down migration for $f"; exit 1; }
done
echo "== up"; for f in $UP; do echo "   $f"; run "$f"; done
if [[ -f supabase/tests/rls.sql ]]; then echo "== rls tests"; run supabase/tests/rls.sql; fi
if [[ -f supabase/tests/gates.sql ]]; then echo "== gates tests"; run supabase/tests/gates.sql; fi
echo "== down"; for f in $(echo "$UP" | sort -r); do d="supabase/migrations/down/$(basename "${f%.sql}").down.sql"; echo "   $d"; run "$d"; done
LEFT=$("${PSQL[@]}" "${TARGET[@]}" -At -o /dev/stdout -c "select count(*) from pg_tables where schemaname='public'")
[[ "$LEFT" == "0" ]] || { echo "down migrations left $LEFT tables in public"; exit 1; }
echo "== up again"; for f in $UP; do run "$f"; done
echo "migrations OK"
