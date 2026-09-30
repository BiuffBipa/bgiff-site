#!/usr/bin/env bash
# Shared-project option (D-B01 alternative): rewrite migrations so all objects live in a named schema.
# Usage: supabase/scripts/set-schema.sh bgiff   → writes to supabase/migrations.bgiff/
set -euo pipefail
SCHEMA="${1:?schema name}"
cd "$(dirname "$0")/.."
OUT="migrations.$SCHEMA"
rm -rf "$OUT"; cp -r migrations "$OUT"
for f in "$OUT"/*.sql "$OUT"/down/*.sql; do
  { echo "create schema if not exists $SCHEMA;"; echo "set search_path = $SCHEMA, public, extensions;"; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
  sed -i "s/schemaname *= *'public'/schemaname = '$SCHEMA'/g; s/n.nspname *= *'public'/n.nspname = '$SCHEMA'/g; s/set search_path = public/set search_path = $SCHEMA, public/g; s/in schema public/in schema $SCHEMA/g; s/on schema public/on schema $SCHEMA/g" "$f"
done
echo "wrote $OUT — expose schema '$SCHEMA' in Supabase API settings and set db.schema in the clients"
