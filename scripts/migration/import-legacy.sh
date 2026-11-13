#!/usr/bin/env bash
# Loads firestore-export.csv into the PerfectTap Supabase project's `legacy` schema.
#   SUPABASE_DB_URL='postgresql://postgres.<ref>:<password>@<pooler-host>:5432/postgres' \
#   EXPECTED_REF=pgvtaotdyspwnpqtxpju ./import-legacy.sh firestore-export.csv
# Refuses to run unless the connection string targets EXPECTED_REF (guards Corelim and the
# retired Singapore project).
set -euo pipefail
CSV="${1:?csv path}"
: "${SUPABASE_DB_URL:?set SUPABASE_DB_URL}"
: "${EXPECTED_REF:?set EXPECTED_REF to the PerfectTap project ref}"
case "$EXPECTED_REF" in
  ulrdeytlwqetfzishxuj|wjyougesuxfkucpmgoyx) echo "Refusing: that is a Corelim project." >&2; exit 2;;
  jhsihajewbhwbuytlrmn) echo "Refusing: that is the retired Singapore project, not PerfectTap (pgvtaotdyspwnpqtxpju)." >&2; exit 2;;
esac
if [[ "$SUPABASE_DB_URL" != *"$EXPECTED_REF"* ]]; then
  echo "Refusing: SUPABASE_DB_URL does not reference $EXPECTED_REF" >&2; exit 2
fi
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 <<SQL
\copy legacy.raw_docs (collection, doc_id, parent_id, data) from '$CSV' csv
select legacy.ingest();
select (select count(*) from legacy.players) as players,
       (select count(*) from legacy.friendships) as friendships,
       (select count(*) from legacy.leaderboard) as leaderboard_rows;
SQL
