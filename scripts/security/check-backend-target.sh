#!/usr/bin/env bash
# Consistency guard for the Supabase target the app ships with (offline, read-only):
#   * ios/PerfectTap/project.yml has exactly one SUPABASE_URL and one publishable key;
#   * SUPABASE_URL ref == supabase/.perfecttap-ref (the ref deploy-supabase.sh deploys to);
#   * the shipped key is a publishable key (never sb_secret_ / a JWT);
#   * Release uses PT_BACKEND=supabase.
# Optional: PT_EXPECTED_PROD_REF=<ref> also requires that exact ref (use before a
# Release / App Review build, after any staging dry-run that repointed the app).
#
#   scripts/security/check-backend-target.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import os, re, sys
yml = open("ios/PerfectTap/project.yml").read()
urls = re.findall(r'^\s*SUPABASE_URL:\s*"https://([a-z0-9]+)\.supabase\.co"', yml, re.M)
keys = re.findall(r'^\s*SUPABASE_PUBLISHABLE_KEY:\s*"([^"]*)"', yml, re.M)
errs = []
if len(urls) != 1: errs.append(f"expected 1 SUPABASE_URL in project.yml, found {len(urls)}")
if len(keys) != 1: errs.append(f"expected 1 SUPABASE_PUBLISHABLE_KEY in project.yml, found {len(keys)}")
elif not keys[0].startswith("sb_publishable_"): errs.append("SUPABASE_PUBLISHABLE_KEY is not an sb_publishable_ key")
ref_file = open("supabase/.perfecttap-ref").read().strip() if os.path.exists("supabase/.perfecttap-ref") else None
if urls and ref_file and urls[0] != ref_file:
    errs.append(f"app points at {urls[0]} but supabase/.perfecttap-ref is {ref_file} (half-switched staging/prod?)")
exp = os.environ.get("PT_EXPECTED_PROD_REF")
if exp and urls and urls[0] != exp:
    errs.append(f"app points at {urls[0]}, expected production ref {exp}")
m = re.search(r"^\s*Release:\s*\n((?:\s{10,}.*\n)+)", yml, re.M)
if not m or not re.search(r"PT_BACKEND:\s*supabase\b", m.group(1)):
    errs.append("Release PT_BACKEND is not 'supabase'")
if errs:
    print("FAIL backend target:", *errs, sep="\n  - ", file=sys.stderr); sys.exit(1)
print(f"PASS: app -> https://{urls[0]}.supabase.co (publishable key), matches supabase/.perfecttap-ref"
      + (f" and expected prod ref" if exp else ""))
PY
