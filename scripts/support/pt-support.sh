#!/usr/bin/env bash
# PerfectTap internal support CLI (owner/operator only).
#
# Talks to Postgres directly with the database connection string, which only
# the owner holds. Support functions are not reachable with the anon or
# service-role keys (see supabase/migrations/20261127120000_support_operations.sql).
#
#   export PT_SUPPORT_DB_URL='postgresql://...'   # never commit / paste in chat
#   export PT_SUPPORT_OPERATOR='oya'              # who is acting (audit log)
#
# Read-only (run inside a READ ONLY transaction):
#   pt-support.sh find <uid|username|friend_code|email>
#   pt-support.sh user <uid> [ledger_limit]
#   pt-support.sh purchase <transaction_id|original_transaction_id>
#   pt-support.sh legacy-queue [limit]
#   pt-support.sh refund-watch [days]
#   pt-support.sh economy-watch [days] [limit]
#
# Mutating (require PT_CONFIRM=yes, operator, ticket, reason; audited):
#   pt-support.sh adjust <uid> <delta> <ticket> "<reason>"
#   pt-support.sh legacy-resolve <uid> <balance> <ticket> "<reason>"
#   pt-support.sh contain economy|purchases <ticket> "<reason>"
#
# Local verification: PT_SUPPORT_DB_URL=postgresql://postgres:postgres@127.0.0.1:55622/postgres
set -euo pipefail
cd "$(dirname "$0")/../.."

die() { echo "pt-support: $*" >&2; exit 2; }
[[ -n "${PT_SUPPORT_DB_URL:-}" ]] || die "set PT_SUPPORT_DB_URL (database connection string)"
command -v psql >/dev/null || die "psql not found"

CORELIM_REFS=("wjyougesuxfkucpmgoyx" "ulrdeytlwqetfzishxuj")
for bad in "${CORELIM_REFS[@]}"; do
  [[ "$PT_SUPPORT_DB_URL" == *"$bad"* ]] && die "REFUSING: connection string points at a Corelim project"
done
# Show the target without the password.
TARGET="$(printf '%s' "$PT_SUPPORT_DB_URL" | sed -E 's#://([^:/@]+)(:[^@]*)?@#://\1:***@#')"
echo "target: $TARGET" >&2

uuid_re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
int_re='^-?[0-9]{1,9}$'

ro() { # read-only query with bound variables
  local sql="$1"; shift
  psql "$PT_SUPPORT_DB_URL" -X -q -v ON_ERROR_STOP=1 "$@" <<SQL
begin read only;
$sql
commit;
SQL
}

rw() { # mutating query; requires explicit confirmation + operator
  local sql="$1"; shift
  [[ "${PT_CONFIRM:-}" == "yes" ]] || die "mutating command: re-run with PT_CONFIRM=yes after reviewing 'user'/'purchase' output"
  [[ -n "${PT_SUPPORT_OPERATOR:-}" ]] || die "set PT_SUPPORT_OPERATOR (your name, stored in the audit log)"
  psql "$PT_SUPPORT_DB_URL" -X -q -v ON_ERROR_STOP=1 -v operator="$PT_SUPPORT_OPERATOR" "$@" <<SQL
begin;
$sql
commit;
SQL
}

cmd="${1:-}"; shift || true
case "$cmd" in
  find)
    [[ $# -eq 1 ]] || die "usage: find <query>"
    ro "select * from private.support_find_user(:'q');" -v q="$1" ;;
  user)
    [[ "${1:-}" =~ $uuid_re ]] || die "usage: user <uid> [ledger_limit]"
    lim="${2:-50}"; [[ "$lim" =~ ^[0-9]{1,3}$ ]] || die "bad ledger_limit"
    ro "select jsonb_pretty(private.support_user_overview(:'u'::uuid, :'l'::int));" -v u="$1" -v l="$lim" -A -t ;;
  purchase)
    [[ $# -eq 1 && "$1" =~ ^[0-9A-Za-z._-]{1,64}$ ]] || die "usage: purchase <transaction_id>"
    ro "select jsonb_pretty(private.support_purchase_lookup(:'t'));" -v t="$1" -A -t ;;
  legacy-queue)
    lim="${1:-100}"; [[ "$lim" =~ ^[0-9]{1,4}$ ]] || die "bad limit"
    ro "select * from private.support_legacy_queue(:'l'::int);" -v l="$lim" ;;
  refund-watch)
    d="${1:-30}"; [[ "$d" =~ ^[0-9]{1,3}$ ]] || die "bad days"
    ro "select * from private.support_refund_watch(:'d'::int);" -v d="$d" ;;
  economy-watch)
    d="${1:-7}"; lim="${2:-50}"
    [[ "$d" =~ ^[0-9]{1,3}$ && "$lim" =~ ^[0-9]{1,4}$ ]] || die "bad args"
    ro "select * from private.support_economy_watch(:'d'::int, :'l'::int);" -v d="$d" -v l="$lim" ;;
  adjust)
    [[ $# -eq 4 && "$1" =~ $uuid_re && "$2" =~ $int_re ]] || die "usage: adjust <uid> <delta> <ticket> \"<reason>\""
    rw "select jsonb_pretty(private.support_adjust_balance(:'u'::uuid, :'d'::bigint, :'operator', :'t', :'r'));" \
       -v u="$1" -v d="$2" -v t="$3" -v r="$4" -A -t ;;
  legacy-resolve)
    [[ $# -eq 4 && "$1" =~ $uuid_re && "$2" =~ ^[0-9]{1,9}$ ]] || die "usage: legacy-resolve <uid> <balance> <ticket> \"<reason>\""
    rw "select jsonb_pretty(private.support_set_legacy_opening(:'u'::uuid, :'b'::bigint, :'operator', :'t', :'r'));" \
       -v u="$1" -v b="$2" -v t="$3" -v r="$4" -A -t ;;
  contain)
    [[ $# -eq 3 ]] || die "usage: contain economy|purchases <ticket> \"<reason>\""
    case "$1" in
      economy)   file="supabase/rollback/20261125200000_economy_containment.sql"; kind="economy_containment" ;;
      purchases) file="supabase/rollback/20261122120000_purchase_containment.sql"; kind="purchase_containment" ;;
      *) die "contain economy|purchases" ;;
    esac
    [[ "${PT_CONFIRM:-}" == "yes" ]] || die "containment: re-run with PT_CONFIRM=yes"
    [[ -n "${PT_SUPPORT_OPERATOR:-}" ]] || die "set PT_SUPPORT_OPERATOR"
    psql "$PT_SUPPORT_DB_URL" -X -q -v ON_ERROR_STOP=1 -f "$file"
    psql "$PT_SUPPORT_DB_URL" -X -q -v ON_ERROR_STOP=1 -v k="$kind" -v o="$PT_SUPPORT_OPERATOR" -v t="$2" -v r="$3" \
      <<< "select private.support_log_containment(:'k', :'o', :'t', :'r');"
    echo "contained: $1 (logged in private.support_actions)" ;;
  ""|-h|--help|help) sed -n '2,24p' "$0" ;;
  *) die "unknown command '$cmd' (see --help)" ;;
esac
