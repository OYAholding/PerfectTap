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
# Re-runnable: a fresh export is staged in a temp table and upserted into legacy.raw_docs
# (a plain \copy into raw_docs fails on the second run with raw_docs_pkey). legacy.ingest()
# then refreshes unclaimed players only. One transaction: any error leaves the DB unchanged.
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 --single-transaction <<SQL
create temp table raw_import (like legacy.raw_docs including defaults) on commit drop;
\copy raw_import (collection, doc_id, parent_id, data) from '$CSV' csv
insert into legacy.raw_docs (collection, doc_id, parent_id, data)
select collection, doc_id, parent_id, data from raw_import
on conflict (collection, parent_id, doc_id) do update set data = excluded.data
  where legacy.raw_docs.data is distinct from excluded.data;
select legacy.ingest();
select (select count(*) from raw_import) as rows_in_export,
       (select count(*) from legacy.players) as players,
       (select count(*) from legacy.friendships) as friendships,
       (select count(*) from legacy.leaderboard) as leaderboard_rows,
       (select count(*) from private.legacy_claims) as claims;
SQL
