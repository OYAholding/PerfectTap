// Just-in-time read of a legacy player's CURRENT Firestore data during the claim.
// Authenticates as the player with their own (already verified) Firebase ID token, so it
// can read only what Firestore's security rules let that player read. No service account.
// Output matches scripts/migration/export-firestore.mjs (same plain-JSON shape).

const PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "perfecttap-48a08";
// Overridable for local integration tests only.
const FIRESTORE_URL = Deno.env.get("FIRESTORE_URL") ?? "https://firestore.googleapis.com";
const DOCS = `${FIRESTORE_URL}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const TIMEOUT_MS = 5000;
const MAX_FRIENDS = 50;

type FsValue = Record<string, unknown>;

export type LatestLegacyPlayer =
  | { kind: "found"; data: Record<string, unknown>; friendUids: string[] }
  | { kind: "not_found" } // Firestore has no player document for this account
  | { kind: "error"; reason: string }; // couldn't read: the caller falls back to the snapshot

function decode(v: FsValue): unknown {
  if ("stringValue" in v) return v.stringValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) {
    const d = Number(v.doubleValue);
    return Number.isFinite(d) ? d : null;
  }
  if ("booleanValue" in v) return v.booleanValue;
  if ("nullValue" in v) return null;
  if ("timestampValue" in v) return new Date(String(v.timestampValue)).toISOString();
  if ("geoPointValue" in v) {
    const g = v.geoPointValue as { latitude?: number; longitude?: number };
    return { lat: g.latitude ?? 0, lng: g.longitude ?? 0 };
  }
  if ("referenceValue" in v) return String(v.referenceValue).replace(/^projects\/[^/]+\/databases\/[^/]+\/documents\//, "");
  if ("bytesValue" in v) return v.bytesValue;
  if ("arrayValue" in v) return ((v.arrayValue as { values?: FsValue[] }).values ?? []).map(decode);
  if ("mapValue" in v) return decodeFields((v.mapValue as { fields?: Record<string, FsValue> }).fields ?? {});
  return null;
}

function decodeFields(fields: Record<string, FsValue>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(fields).map(([k, x]) => [k, decode(x)]));
}

async function fsFetch(path: string, idToken: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${DOCS}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${idToken}`, "Content-Type": "application/json" },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
}

async function getPlayer(uid: string, idToken: string): Promise<Record<string, unknown> | null | "error"> {
  const res = await fsFetch(`/players/${encodeURIComponent(uid)}`, idToken);
  if (res.status === 404) return null;
  if (!res.ok) return "error";
  const doc = await res.json() as { fields?: Record<string, FsValue> };
  return decodeFields(doc.fields ?? {});
}

/** Friend uids Firestore confirms: canonical friendships + mutual players.friends mirrors. */
async function confirmedFriends(uid: string, idToken: string, player: Record<string, unknown>): Promise<string[]> {
  const out = new Set<string>();
  try {
    const res = await fsFetch(":runQuery", idToken, {
      method: "POST",
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: "friendships" }],
          where: { fieldFilter: { field: { fieldPath: "user_ids" }, op: "ARRAY_CONTAINS", value: { stringValue: uid } } },
          limit: 200,
        },
      }),
    });
    if (res.ok) {
      const rows = await res.json() as { document?: { fields?: Record<string, FsValue> } }[];
      for (const r of rows) {
        const ids = r.document?.fields ? decodeFields(r.document.fields).user_ids : null;
        if (Array.isArray(ids) && ids.length === 2 && ids.includes(uid)) {
          const other = ids[0] === uid ? ids[1] : ids[0];
          if (typeof other === "string" && other !== uid) out.add(other);
        }
      }
    }
  } catch { /* friendships are best effort; the snapshot still has the old ones */ }

  // Older app versions wrote only players.friends. Count a pair only when BOTH sides list each other.
  const mirror = Array.isArray(player.friends)
    ? (player.friends as unknown[]).filter((f): f is string => typeof f === "string" && f !== uid && !out.has(f))
    : [];
  const checks = await Promise.all(mirror.slice(0, MAX_FRIENDS).map(async (f) => {
    try {
      const other = await getPlayer(f, idToken);
      return other && other !== "error" && Array.isArray(other.friends) && other.friends.includes(uid) ? f : null;
    } catch {
      return null;
    }
  }));
  for (const f of checks) if (f) out.add(f);
  return [...out];
}

export async function fetchLatestLegacyPlayer(uid: string, idToken: string): Promise<LatestLegacyPlayer> {
  try {
    const player = await getPlayer(uid, idToken);
    if (player === "error") return { kind: "error", reason: "read_failed" };
    if (player === null) return { kind: "not_found" };
    if (typeof player.uid === "string" && player.uid !== uid) return { kind: "error", reason: "uid_mismatch" };
    return { kind: "found", data: player, friendUids: await confirmedFriends(uid, idToken, player) };
  } catch (e) {
    return { kind: "error", reason: e instanceof DOMException && e.name === "TimeoutError" ? "timeout" : "fetch_failed" };
  }
}
