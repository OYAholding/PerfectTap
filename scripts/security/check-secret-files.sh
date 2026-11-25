#!/usr/bin/env bash
# Secret-leak guard for tracked files (complements gitleaks in CI).
#
#   scripts/security/check-secret-files.sh             # check tracked files of this repo
#   scripts/security/check-secret-files.sh --self-test # prove detection on fixtures
#   scripts/security/check-secret-files.sh --root DIR  # check another checkout
#
# FAILS when a tracked file is:
#   * a signing / API credential by type: *.p8 (App Store Connect / APNs / Sign in
#     with Apple keys), AuthKey_*.p8, *.p12, *.mobileprovision, *.cer, *.pem, *.key
#   * an env file: asc.env, .env, .env.* (except *.example / *.sample / *.template)
#   * a Google service account / Firebase admin SDK JSON
# or when tracked text content contains:
#   * a PEM private key block
#   * a Supabase secret key (sb_secret_...)
#   * a Supabase service_role JWT (payload with "role":"service_role")
#   * an assignment of a non-empty literal to SUPABASE_SERVICE_ROLE_KEY / SERVICE_ROLE_KEY /
#     ASC_KEY_CONTENT / APP_STORE_CONNECT_API_KEY_CONTENT / APPLE_PRIVATE_KEY
# Publishable keys (sb_publishable_...) and the public Firebase iOS API key are allowed.
# Exit 0 = clean, 1 = finding, 2 = usage.
set -euo pipefail

run_check() {
  python3 - "$1" <<'PY'
import base64, json, os, re, subprocess, sys

root = sys.argv[1]
SELF = "scripts/security/check-secret-files.sh"

def tracked():
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], check=True, capture_output=True).stdout.decode()
        names = [n for n in out.split("\0") if n]
        if names:
            return names
    except Exception:
        pass
    res = []
    for d, dirs, fs in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".git", "node_modules", "DerivedData", "build")]
        res += [os.path.relpath(os.path.join(d, f), root) for f in fs]
    return res

BAD_NAME = [
    (re.compile(r"(^|/)AuthKey_[^/]*\.p8$"), "App Store Connect / Apple private key"),
    (re.compile(r"\.p8$"), "Apple .p8 private key"),
    (re.compile(r"\.(p12|pfx)$"), "PKCS#12 certificate bundle"),
    (re.compile(r"\.mobileprovision$"), "provisioning profile"),
    (re.compile(r"\.(cer|pem|key)$"), "certificate / key file"),
    (re.compile(r"(^|/)asc\.env$"), "App Store Connect credentials env"),
    (re.compile(r"(^|/)\.env$"), "env file"),
    (re.compile(r"(^|/)\.env\.(?!example$|sample$|template$)[^/]+$"), "env file"),
    (re.compile(r"(^|/)[^/]*\.env$"), "env file"),
    (re.compile(r"(^|/)(service-account[^/]*|[^/]*-adminsdk-[^/]*)\.json$"), "Google service account JSON"),
]
ALLOW_NAME = re.compile(r"\.(example|sample|template)$")

PEM = re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----")
SB_SECRET = re.compile(r"sb_secret_[A-Za-z0-9_\-]{20,}")
JWT = re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.(eyJ[A-Za-z0-9_\-]{10,})\.[A-Za-z0-9_\-]{10,}")
ASSIGN = re.compile(r"""\b(SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY|ASC_KEY_CONTENT|APP_STORE_CONNECT_API_KEY_CONTENT|APPLE_PRIVATE_KEY)\b\s*[:=]\s*["']?([A-Za-z0-9+/=_\-\.]{24,})""")

def jwt_role(payload):
    try:
        pad = "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload + pad)).get("role")
    except Exception:
        return None

findings = []
for rel in tracked():
    if rel == SELF:
        continue
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        continue
    if not ALLOW_NAME.search(rel):
        for rx, why in BAD_NAME:
            if rx.search(rel):
                findings.append(f"{rel}: tracked {why}")
                break
    try:
        if os.path.getsize(p) > 5_000_000:
            continue
        text = open(p, encoding="utf-8", errors="strict").read()
    except Exception:
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if PEM.search(line):
            findings.append(f"{rel}:{n}: PEM private key block")
        if SB_SECRET.search(line):
            findings.append(f"{rel}:{n}: Supabase secret key (sb_secret_...)")
        for m in JWT.finditer(line):
            if jwt_role(m.group(1)) == "service_role":
                findings.append(f"{rel}:{n}: Supabase service_role JWT")
        m = ASSIGN.search(line)
        if m and not m.group(2).startswith(("$", "${", "env(", "Deno.env")):
            findings.append(f"{rel}:{n}: literal value assigned to {m.group(1)}")

if findings:
    print(f"FAIL: {len(findings)} secret-leak finding(s):", file=sys.stderr)
    for f in findings:
        print("  - " + f, file=sys.stderr)
    print("Remove the file from git (git rm --cached), rotate the credential, and keep it in a local, ignored location.", file=sys.stderr)
    sys.exit(1)
print("PASS: no credential files, private keys, service-role keys or asc.env tracked.")
PY
}

self_test() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  local fails=0
  expect() {
    local want="$1" name="$2" got=0
    run_check "$tmp/$name" >/dev/null 2>&1 || got=$?
    if [[ "$got" == "$want" ]]; then echo "  ok   $name (exit $got)"; else echo "  FAIL $name (want $want, got $got)"; fails=$((fails+1)); fi
  }
  mkdir -p "$tmp"/{clean,p8,ascenv,sbsecret,jwt,pem,assign,envexample}
  echo 'SUPABASE_PUBLISHABLE_KEY: "sb_publishable_abcdefghijklmnopqrstuvwxyz"' > "$tmp/clean/project.yml"
  echo 'const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")' > "$tmp/clean/index.ts"
  expect 0 clean
  echo x > "$tmp/p8/AuthKey_ABC123.p8"; expect 1 p8
  echo 'ASC_KEY_ID=1' > "$tmp/ascenv/asc.env"; expect 1 ascenv
  echo "k=sb_secret_$(printf 'a%.0s' {1..30})" > "$tmp/sbsecret/x.txt"; expect 1 sbsecret
  local payload; payload="$(printf '{"iss":"supabase","role":"service_role"}' | base64 | tr '+/' '-_' | tr -d '=\n')"
  echo "key: eyJhbGciOiJIUzI1NiJ9.${payload}.abcdefghijklmnop" > "$tmp/jwt/a.md"; expect 1 jwt
  printf -- '-----BEGIN PRIVATE KEY-----\nMIIB\n' > "$tmp/pem/notes.txt"; expect 1 pem
  echo 'SUPABASE_SERVICE_ROLE_KEY=abcdefghijklmnopqrstuvwxyz0123456789' > "$tmp/assign/run.sh"; expect 1 assign
  echo 'ASC_KEY_ID=' > "$tmp/envexample/asc.env.example"; expect 0 envexample
  if [[ "$fails" -eq 0 ]]; then echo "self-test PASS"; else echo "self-test FAIL ($fails)"; return 1; fi
}

case "${1:-}" in
  --self-test) self_test ;;
  --root) run_check "${2:?--root DIR}" ;;
  "") run_check "$(cd "$(dirname "$0")/../.." && pwd)" ;;
  *) echo "usage: $0 [--self-test | --root DIR]" >&2; exit 2 ;;
esac
