#!/usr/bin/env bash
# Release-safety guard: FAILS if any monetization / economy kill-switch is turned
# on for a non-Debug (Release, Profile, Staging, ...) build configuration.
#
#   scripts/security/check-monetization-flags.sh            # check the repo
#   scripts/security/check-monetization-flags.sh --self-test  # prove the checker catches violations
#   scripts/security/check-monetization-flags.sh --root DIR   # check another checkout
#
# Guarded flags (all must stay literal NO outside Debug until the owner-approved
# activation step in docs/RELEASE_1.2.0_RUNBOOK.he.md):
#   PT_IAP_CATALOG_ENABLED  PT_IAP_SERVER_VERIFICATION_ENABLED  PT_IAP_COIN_PACKS_ENABLED
#   PT_IAP_REMOVE_ADS_ENABLED  PT_IAP_PREMIUM_SKINS_ENABLED  PT_AUTHORITATIVE_ECONOMY_ENABLED
#
# What is inspected (every tracked file of these kinds, not just ios/PerfectTap):
#   * project.yml (XcodeGen): any flag = YES in `settings.base` (applies to Release),
#     in `configs.<non-Debug>` or in `configSettings`, at project or target level.
#   * *.pbxproj: every XCBuildConfiguration whose name is not "Debug".
#   * *.xcconfig: any file whose name does not contain "debug".
#   * Info.plist / *.plist: a flag hard-coded to YES/true instead of $(FLAG).
# A value that is not a literal NO/false (e.g. "$(OTHER)") outside Debug is also a
# failure: the guard must be able to prove the flag is off.
# Requires only bash + python3 (no PyYAML). Exit 0 = safe, 1 = violation, 2 = usage.
set -euo pipefail

FLAGS="PT_IAP_CATALOG_ENABLED PT_IAP_SERVER_VERIFICATION_ENABLED PT_IAP_COIN_PACKS_ENABLED PT_IAP_REMOVE_ADS_ENABLED PT_IAP_PREMIUM_SKINS_ENABLED PT_AUTHORITATIVE_ECONOMY_ENABLED"

run_check() {
  local root="$1"
  PT_FLAGS="$FLAGS" python3 - "$root" <<'PY'
import os, re, subprocess, sys

root = sys.argv[1]
FLAGS = os.environ["PT_FLAGS"].split()
OFF = {"no", "false", "0"}
violations, checked = [], {"project.yml": 0, "pbxproj": 0, "xcconfig": 0, "plist": 0}

def files():
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], check=True,
                             capture_output=True).stdout.decode()
        names = [n for n in out.split("\0") if n]
        if names:
            return names
    except Exception:
        pass
    found = []
    for d, dirs, fs in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".git", "DerivedData", "build", "node_modules")]
        found += [os.path.relpath(os.path.join(d, f), root) for f in fs]
    return found

def norm(v):
    return v.strip().strip(";").strip().strip('"').strip("'").strip()

def bad(where, flag, value, why):
    violations.append(f"{where}: {flag} = {value!r} ({why})")

def judge(where, flag, value):
    v = norm(value)
    if v.lower() in OFF:
        return
    if v.upper() == "YES" or v.lower() in ("true", "1"):
        bad(where, flag, v, "flag ENABLED outside Debug")
    else:
        bad(where, flag, v, "not a literal NO outside Debug; cannot prove it is off")

def check_project_yml(path, rel):
    checked["project.yml"] += 1
    stack = []  # (indent, key)
    for n, raw in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        line = raw.split(" #", 1)[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not line.strip() or line.lstrip().startswith("- "):
            continue
        indent = len(line) - len(line.lstrip())
        m = re.match(r"\s*([A-Za-z0-9_.\-\"']+)\s*:(.*)$", line)
        if not m:
            continue
        key, val = norm(m.group(1)), m.group(2).strip()
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if key in FLAGS:
            path_keys = [k for _, k in stack]
            # Which build configuration does this setting apply to?
            cfg = None
            for i, k in enumerate(path_keys):
                if k in ("configs", "configSettings") and i + 1 < len(path_keys):
                    cfg = path_keys[i + 1]
            if "settings" not in path_keys and "configSettings" not in path_keys:
                # e.g. Info.plist `properties: PT_X: $(PT_X)` — only literal YES is a problem.
                if norm(val).upper() == "YES" or norm(val).lower() == "true":
                    bad(f"{rel}:{n} [{'/'.join(path_keys)}]", key, norm(val), "hard-coded ON in Info.plist properties")
                continue
            if cfg is not None and cfg.lower() == "debug":
                continue
            scope = cfg if cfg else "base (applies to Release)"
            judge(f"{rel}:{n} [{'/'.join(path_keys)} -> {scope}]", key, val)
        if val == "":
            stack.append((indent, key))

def check_pbxproj(path, rel):
    checked["pbxproj"] += 1
    text = open(path, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"(\w+) /\* ([^*]*?) \*/ = \{\s*isa = XCBuildConfiguration;(.*?)\n\t\t\};", text, re.S):
        body = m.group(3)
        nm = re.search(r"\n\s*name = \"?([^\";]+)\"?;", body)
        name = nm.group(1) if nm else m.group(2)
        if is_debug_config(name):
            continue
        line_no = text.count("\n", 0, m.start()) + 1
        for flag in FLAGS:
            if name in IAP_CEILING_CONFIGS and flag in IAP_CEILING_FLAGS:
                continue
            for fm in re.finditer(r"\b" + flag + r"\s*=\s*([^;\n]+);", body):
                judge(f"{rel}:{line_no} [XCBuildConfiguration {m.group(1)} '{name}']", flag, fm.group(1))

# Opt-in App Store purchase ceiling (docs/MONETIZATION_ACTIVATION_STRATEGY.md):
# a configuration named here may compile PT_IAP_* = YES because sales are still
# gated at runtime by the server sales switch (fails closed). The shipping
# `Release` configuration and the authoritative-economy flag are never exempt.
IAP_CEILING_CONFIGS = {"Release-IAP"}
IAP_CEILING_FLAGS = {f for f in FLAGS if f.startswith("PT_IAP_")}

def is_debug_config(name):
    return name.lower() == "debug" or name.lower().startswith("debug-")

def xcconfig_users():
    """Map xcconfig basename -> set of build configurations using it (XcodeGen configFiles)."""
    users = {}
    for rel in files():
        if os.path.basename(rel) != "project.yml":
            continue
        in_block, block_indent = False, 0
        for raw in open(os.path.join(root, rel), encoding="utf-8", errors="replace"):
            if not raw.strip() or raw.lstrip().startswith("#"):
                continue
            indent = len(raw) - len(raw.lstrip())
            if re.match(r"\s*configFiles\s*:\s*$", raw):
                in_block, block_indent = True, indent
                continue
            if in_block and indent <= block_indent:
                in_block = False
            if in_block:
                m = re.match(r"\s*([\w.\-]+)\s*:\s*(\S+\.xcconfig)", raw)
                if m:
                    users.setdefault(os.path.basename(m.group(2)), set()).add(m.group(1))
    return users

def check_xcconfig(path, rel):
    configs = XCCONFIG_USERS.get(os.path.basename(rel))
    if configs and all(is_debug_config(c) for c in configs):
        return
    if not configs and "debug" in os.path.basename(rel).lower():
        return
    ceiling = bool(configs) and all(is_debug_config(c) or c in IAP_CEILING_CONFIGS for c in configs)
    checked["xcconfig"] += 1
    for n, raw in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        line = raw.split("//", 1)[0]
        for flag in FLAGS:
            m = re.match(r"\s*" + flag + r"(\[[^\]]*\])?\s*=\s*(.*)$", line)
            if m:
                cond = m.group(1) or ""
                if "config=debug" in cond.lower().replace(" ", ""):
                    continue
                if ceiling and flag in IAP_CEILING_FLAGS:
                    continue
                judge(f"{rel}:{n} [used by {', '.join(sorted(configs or {'<unmapped>'}))}]", flag, m.group(2))

def check_plist(path, rel):
    try:
        text = open(path, encoding="utf-8", errors="strict").read()
    except Exception:
        return  # binary plist: not used for these flags
    checked["plist"] += 1
    for flag in FLAGS:
        for m in re.finditer(r"<key>" + flag + r"</key>\s*<(true/|string>\s*(YES|yes|true|TRUE|1)\s*</string)>", text):
            n = text.count("\n", 0, m.start()) + 1
            bad(f"{rel}:{n}", flag, m.group(0).split(">", 1)[1], "hard-coded ON in plist (must be $(FLAG) or NO)")

XCCONFIG_USERS = xcconfig_users()
for rel in files():
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        continue
    base = os.path.basename(rel)
    if base == "project.yml" or base.endswith(".xcodegen.yml"):
        check_project_yml(p, rel)
    elif base == "project.pbxproj":
        check_pbxproj(p, rel)
    elif base.endswith(".xcconfig"):
        check_xcconfig(p, rel)
    elif base.endswith(".plist") and "/Pods/" not in rel and "legacy/" not in rel:
        check_plist(p, rel)

print("monetization-flag guard: inspected "
      + ", ".join(f"{v} {k}" for k, v in checked.items()))
if checked["project.yml"] == 0 and checked["pbxproj"] == 0:
    print("FAIL: no project.yml or project.pbxproj found — guard cannot verify anything", file=sys.stderr)
    sys.exit(1)
if violations:
    print(f"FAIL: {len(violations)} monetization flag violation(s) outside Debug:", file=sys.stderr)
    for v in violations:
        print("  - " + v, file=sys.stderr)
    print("These flags may only be turned on through the owner-approved activation gate "
          "(docs/RELEASE_1.2.0_RUNBOOK.he.md).", file=sys.stderr)
    sys.exit(1)
print("PASS: shipping Release has every monetization/economy flag NO; only the opt-in Release-IAP ceiling may compile PT_IAP_* (server-gated); PT_AUTHORITATIVE_ECONOMY_ENABLED is NO everywhere outside Debug.")
PY
}

self_test() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  local fails=0
  expect() {  # expect <0|1> <name>
    local want="$1" name="$2" got=0
    run_check "$tmp/$name" >/dev/null 2>&1 || got=$?
    if [[ "$got" == "$want" ]]; then echo "  ok   $name (exit $got)"; else echo "  FAIL $name (want $want, got $got)"; fails=$((fails+1)); fi
  }
  mk() { mkdir -p "$tmp/$1"; cat > "$tmp/$1/$2"; }

  mk safe project.yml <<'Y'
targets:
  App:
    settings:
      base:
        PRODUCT_NAME: App
      configs:
        Debug:
          PT_IAP_CATALOG_ENABLED: "YES"
        Release:
          PT_IAP_CATALOG_ENABLED: "NO"
          PT_AUTHORITATIVE_ECONOMY_ENABLED: NO
    info:
      properties:
        PT_IAP_CATALOG_ENABLED: $(PT_IAP_CATALOG_ENABLED)
Y
  expect 0 safe

  mk yml-release project.yml <<'Y'
targets:
  App:
    settings:
      configs:
        Release:
          PT_IAP_COIN_PACKS_ENABLED: "YES"   # oops
Y
  expect 1 yml-release

  mk yml-base project.yml <<'Y'
settings:
  base:
    PT_AUTHORITATIVE_ECONOMY_ENABLED: YES
Y
  expect 1 yml-base

  mk yml-indirect project.yml <<'Y'
targets:
  App:
    settings:
      configs:
        Release:
          PT_IAP_REMOVE_ADS_ENABLED: $(SOMETHING)
Y
  expect 1 yml-indirect

  mk yml-plist-hardcoded project.yml <<'Y'
targets:
  App:
    info:
      properties:
        PT_IAP_PREMIUM_SKINS_ENABLED: "YES"
Y
  expect 1 yml-plist-hardcoded

  printf '\t\tAAA /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tPT_IAP_CATALOG_ENABLED = YES;\n\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n\t\tBBB /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tPT_IAP_CATALOG_ENABLED = NO;\n\t\t\t};\n\t\t\tname = Release;\n\t\t};\n' | mk pbx-safe project.pbxproj
  expect 0 pbx-safe

  printf '\t\tBBB /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tPT_IAP_SERVER_VERIFICATION_ENABLED = YES;\n\t\t\t};\n\t\t\tname = Release;\n\t\t};\n' | mk pbx-release project.pbxproj
  expect 1 pbx-release

  mk xc project.yml <<'Y'
name: X
Y
  printf 'PT_IAP_COIN_PACKS_ENABLED = YES\n' > "$tmp/xc/Release.xcconfig"
  expect 1 xc

  mk xc-debug project.yml <<'Y'
name: X
Y
  printf 'PT_IAP_COIN_PACKS_ENABLED = YES\n' > "$tmp/xc-debug/Debug.xcconfig"
  expect 0 xc-debug

  mk plist project.yml <<'Y'
name: X
Y
  printf '<plist><dict><key>PT_IAP_CATALOG_ENABLED</key><true/></dict></plist>\n' > "$tmp/plist/Info.plist"
  expect 1 plist

  mk ceiling project.yml <<'Y'
targets:
  App:
    configFiles:
      Debug: Config/Off.xcconfig
      Release: Config/Off.xcconfig
      Release-IAP: Config/IAP.xcconfig
Y
  mkdir -p "$tmp/ceiling/Config"
  printf 'PT_IAP_CATALOG_ENABLED = NO\nPT_AUTHORITATIVE_ECONOMY_ENABLED = NO\n' > "$tmp/ceiling/Config/Off.xcconfig"
  printf 'PT_IAP_CATALOG_ENABLED = YES\nPT_AUTHORITATIVE_ECONOMY_ENABLED = NO\n' > "$tmp/ceiling/Config/IAP.xcconfig"
  expect 0 ceiling

  mk ceiling-economy project.yml <<'Y'
targets:
  App:
    configFiles:
      Release-IAP: Config/IAP.xcconfig
Y
  mkdir -p "$tmp/ceiling-economy/Config"
  printf 'PT_IAP_CATALOG_ENABLED = YES\nPT_AUTHORITATIVE_ECONOMY_ENABLED = YES\n' > "$tmp/ceiling-economy/Config/IAP.xcconfig"
  expect 1 ceiling-economy

  mk ceiling-shared project.yml <<'Y'
targets:
  App:
    configFiles:
      Release: Config/IAP.xcconfig
      Release-IAP: Config/IAP.xcconfig
Y
  mkdir -p "$tmp/ceiling-shared/Config"
  printf 'PT_IAP_COIN_PACKS_ENABLED = YES\n' > "$tmp/ceiling-shared/Config/IAP.xcconfig"
  expect 1 ceiling-shared

  mkdir -p "$tmp/empty"
  expect 1 empty

  if [[ "$fails" -eq 0 ]]; then echo "self-test PASS"; else echo "self-test FAIL ($fails)"; return 1; fi
}

case "${1:-}" in
  --self-test) self_test ;;
  "") run_check "$(cd "$(dirname "$0")/../.." && pwd)" ;;
  --root) run_check "${2:?--root DIR}" ;;
  -h|--help) sed -n '2,22p' "$0" ;;
  *) echo "usage: $0 [--self-test | --root DIR]" >&2; exit 2 ;;
esac
