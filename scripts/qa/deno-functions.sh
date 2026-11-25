#!/usr/bin/env bash
# Static checks + unit tests for EVERY Supabase Edge Function (offline, no Supabase
# project, no secrets). Used by CI (.github/workflows/ci.yml, job `edge-functions`)
# and runnable locally:
#
#   scripts/qa/deno-functions.sh
#
# For each supabase/functions/<fn>/ that has an index.ts:
#   deno fmt --check   deno lint   deno check (with <fn>/deno.json import map + lock)
#   deno test          (*.test.ts / *_test.ts inside <fn>/, if any)
# plus supabase/functions/_shared: fmt, lint and its tests (e.g. purchases.test.ts); its
# modules are type-checked through each importing function.
# New functions are picked up automatically. Exit 0 = all pass, 1 = any step failed.
set -uo pipefail
export NO_COLOR=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FN_DIR="$ROOT/supabase/functions"
cd "$ROOT"
command -v deno >/dev/null || { echo "deno not installed"; exit 2; }
echo "deno: $(deno --version | head -1)"

failed=()
step() {  # step <label> <cmd...>
  local label="$1"; shift
  if "$@" > /tmp/pt-deno-step.log 2>&1; then
    echo "  PASS  $label"
  else
    echo "  FAIL  $label"; sed 's/^/        /' /tmp/pt-deno-step.log | tail -40
    failed+=("$label")
  fi
}

shopt -s nullglob
for dir in "$FN_DIR"/*/; do
  name="$(basename "$dir")"
  rel="supabase/functions/$name"
  ts=( "$dir"*.ts )
  [[ ${#ts[@]} -gt 0 ]] || continue
  cfg=()
  [[ -f "$dir/deno.json" ]] && cfg=(--config "$dir/deno.json")
  echo "== $rel"
  step "$name: fmt"  deno fmt --check "${ts[@]}"
  step "$name: lint" deno lint ${cfg[@]+"${cfg[@]}"} "${ts[@]}"
  if [[ -f "$dir/index.ts" ]]; then
    step "$name: check" deno check ${cfg[@]+"${cfg[@]}"} "$dir/index.ts"
  fi
  # _shared has no import map of its own: its modules are type-checked through every
  # function that imports them (above) and its tests are type-checked by `deno test`.
  tests=( "$dir"*.test.ts "$dir"*_test.ts )
  if [[ ${#tests[@]} -gt 0 ]]; then
    tcfg=(${cfg[@]+"${cfg[@]}"})
    [[ ${#tcfg[@]} -eq 0 ]] && tcfg=(--config "$FN_DIR/verify-purchase/deno.json")
    step "$name: test" deno test --allow-env --allow-read ${tcfg[@]+"${tcfg[@]}"} "${tests[@]}"
  fi
done

echo
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "edge functions: ALL PASS"
  exit 0
fi
echo "edge functions: ${#failed[@]} FAILED step(s): ${failed[*]}"
exit 1
