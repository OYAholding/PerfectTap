"""Reads `supabase projects list -o json` on stdin; exits non-zero unless
<ref> is a PerfectTap project in the OYA Games org, in an EU region."""
import json
import sys

ref, org = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
projects = data["projects"] if isinstance(data, dict) else data
match = [p for p in projects if p.get("ref", p.get("id")) == ref]
if not match:
    sys.exit(f"REFUSING: project {ref} not visible to this CLI login")
p = match[0]
name, region, owner = p.get("name", ""), p.get("region", ""), p.get("organization_id")
if owner != org:
    sys.exit(f"REFUSING: {ref} is in org {owner}, expected {org} (OYA Games)")
if "corelim" in name.lower() or "perfecttap" not in name.lower().replace(" ", ""):
    sys.exit(f"REFUSING: unexpected project name {name!r}")
if not region.startswith("eu-"):
    sys.exit(f"REFUSING: {ref} is in {region}; PerfectTap must be in an EU region")
print(f"Target verified: name={name!r} ref={ref} org={org} region={region} status={p.get('status')}")
