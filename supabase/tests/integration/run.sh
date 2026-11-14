#!/usr/bin/env bash
# Runs the integration suite against the LOCAL stack only (project_id = perfecttap).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB_URL="postgresql://postgres:postgres@127.0.0.1:55622/postgres"
STATUS=$(supabase status -o json 2>/dev/null)
PUB=$(echo "$STATUS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["PUBLISHABLE_KEY"])')

supabase db reset --local >/dev/null 2>&1
# db reset restarts Realtime; wait until it reports healthy (+ replication warm-up).
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' supabase_realtime_perfecttap 2>/dev/null)" = "healthy" ] && break
  sleep 1
done
sleep 5
psql "$DB_URL" -q -v ON_ERROR_STOP=1 -f supabase/tests/integration/fixtures/legacy.psql

# Edge runtime (in Docker) must reach the fake Firebase server on the host:
# host.docker.internal on macOS/Windows, the Supabase network gateway on Linux CI.
HOST_ALIAS=host.docker.internal
if [ "$(uname)" = "Linux" ]; then
  HOST_ALIAS=$(docker network inspect supabase_network_perfecttap -f '{{(index .IPAM.Config 0).Gateway}}')
fi
cat > /tmp/perfecttap-functions.env <<ENV
FIREBASE_PROJECT_ID=perfecttap-48a08
FIREBASE_JWKS_URL=http://$HOST_ALIAS:55699/jwks
FIREBASE_IDENTITY_URL=http://$HOST_ALIAS:55699
FIREBASE_WEB_API_KEY=test-key
FIRESTORE_URL=http://$HOST_ALIAS:55699
ENV
supabase functions serve --env-file /tmp/perfecttap-functions.env >/tmp/perfecttap-functions.log 2>&1 &
SERVE_PID=$!
trap 'kill $SERVE_PID 2>/dev/null || true' EXIT
sleep 6
SB_URL="http://127.0.0.1:55621" SB_PUBLISHABLE_KEY="$PUB" deno test -A --config supabase/tests/integration/deno.json supabase/tests/integration/backend.test.ts
