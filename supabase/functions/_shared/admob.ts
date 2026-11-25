// AdMob rewarded-ad server-side verification (SSV).
// https://developers.google.com/admob/android/ssv
//
// Google calls our URL with a GET query whose last two parameters are
// `signature` (web-safe base64, DER-encoded ECDSA P-256/SHA-256) and `key_id`.
// The signed message is the raw query string before "&signature=". Public keys
// come from https://www.gstatic.com/admob/reward/verifier-keys.json.
//
// Pure logic + injectable key source, so it is unit-tested with a locally
// generated key (admob.test.ts). No Supabase imports here.

export const ADMOB_KEYS_URL =
  "https://www.gstatic.com/admob/reward/verifier-keys.json";

export const REWARDED_SOURCES = new Set([
  "home_rewarded",
  "double_coins",
  "revive",
  "season_progress",
]);

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TRANSACTION_RE = /^[A-Za-z0-9._:-]{1,128}$/;

export type KeyLookup = (keyId: string) => Promise<CryptoKey | null>;

export interface SignedQuery {
  message: Uint8Array<ArrayBuffer>;
  signature: Uint8Array<ArrayBuffer>;
  keyId: string;
  params: URLSearchParams;
}

export function base64UrlDecode(input: string): Uint8Array<ArrayBuffer> {
  const b64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Splits the raw query into the signed part and the signature/key_id. */
export function splitSignedQuery(rawQuery: string): SignedQuery | null {
  const query = rawQuery.startsWith("?") ? rawQuery.slice(1) : rawQuery;
  const at = query.indexOf("&signature=");
  if (at <= 0) return null;
  const tail = new URLSearchParams(query.slice(at + 1));
  const signature = tail.get("signature") ?? "";
  const keyId = tail.get("key_id") ?? "";
  if (!signature || !/^[0-9]{1,20}$/.test(keyId)) return null;
  // Nothing but signature and key_id may follow the signed part.
  for (const name of tail.keys()) {
    if (name !== "signature" && name !== "key_id") return null;
  }
  let sig: Uint8Array<ArrayBuffer>;
  try {
    sig = base64UrlDecode(signature);
  } catch {
    return null;
  }
  return {
    message: new TextEncoder().encode(query.slice(0, at)),
    signature: sig,
    keyId,
    params: new URLSearchParams(query.slice(0, at)),
  };
}

/** DER ECDSA signature → IEEE P1363 (r || s), as WebCrypto expects. */
export function derToP1363(
  der: Uint8Array,
  size = 32,
): Uint8Array<ArrayBuffer> | null {
  let i = 0;
  if (der[i++] !== 0x30) return null;
  let len = der[i++];
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n !== 1) return null;
    len = der[i++];
  }
  if (len !== der.length - i) return null;
  const out = new Uint8Array(size * 2);
  for (let part = 0; part < 2; part++) {
    if (der[i++] !== 0x02) return null;
    const intLen = der[i++];
    if (intLen === undefined || i + intLen > der.length) return null;
    let int = der.subarray(i, i + intLen);
    i += intLen;
    while (int.length > size && int[0] === 0) int = int.subarray(1);
    if (int.length > size) return null;
    out.set(int, part * size + (size - int.length));
  }
  return i === der.length ? out : null;
}

export async function verifySignedQuery(
  rawQuery: string,
  lookup: KeyLookup,
): Promise<URLSearchParams | null> {
  const signed = splitSignedQuery(rawQuery);
  if (!signed) return null;
  const key = await lookup(signed.keyId);
  if (!key) return null;
  const raw = derToP1363(signed.signature);
  if (!raw) return null;
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    raw,
    signed.message,
  );
  return ok ? signed.params : null;
}

export async function importVerifierKey(
  base64Spki: string,
): Promise<CryptoKey> {
  const der = Uint8Array.from(atob(base64Spki), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "spki",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
}

/**
 * Cached key source for Google's published verifier keys. Keys are cached for
 * `ttlMs`; an unknown key_id triggers at most one refetch per `minRefetchMs`
 * (Google rotates keys; this also bounds abuse with random key ids).
 */
export function makeGoogleKeyLookup(
  fetchFn: typeof fetch = fetch,
  ttlMs = 24 * 60 * 60 * 1000,
  minRefetchMs = 5 * 60 * 1000,
  now: () => number = Date.now,
): KeyLookup {
  let keys = new Map<string, CryptoKey>();
  let fetchedAt = 0;
  let inflight: Promise<void> | null = null;

  async function refresh(): Promise<void> {
    const res = await fetchFn(ADMOB_KEYS_URL, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) throw new Error(`verifier_keys_http_${res.status}`);
    const body = await res.json() as {
      keys?: { keyId?: number | string; base64?: string }[];
    };
    const next = new Map<string, CryptoKey>();
    for (const k of body.keys ?? []) {
      if (k.keyId === undefined || typeof k.base64 !== "string") continue;
      try {
        next.set(String(k.keyId), await importVerifierKey(k.base64));
      } catch {
        // Skip a malformed key; others stay usable.
      }
    }
    if (next.size === 0) throw new Error("verifier_keys_empty");
    keys = next;
    fetchedAt = now();
  }

  async function ensure(force: boolean): Promise<void> {
    const age = now() - fetchedAt;
    if (!force && fetchedAt && age < ttlMs) return;
    if (force && fetchedAt && age < minRefetchMs) return;
    inflight ??= refresh().finally(() => (inflight = null));
    await inflight;
  }

  return async (keyId) => {
    try {
      await ensure(false);
      if (!keys.has(keyId)) await ensure(true);
    } catch (error) {
      // Serve stale keys if Google is briefly unreachable.
      if (keys.size === 0) throw error;
    }
    return keys.get(keyId) ?? null;
  };
}

export interface RewardClaim {
  eventKey: string;
  source: string;
  claimIndex: number | null;
  referenceEventKey: string | null;
}

/**
 * custom_data set by the app (ServerSideVerificationOptions.customRewardString).
 * Accepted forms (URLSearchParams already percent-decoded it):
 *   JSON  {"event_key":"<uuid>","source":"double_coins","claim_index":1,"reference_event_key":"<uuid>"}
 *   pipe  <event_key>|<source>|<claim_index>[|<reference_event_key>]
 */
export function parseCustomData(raw: string | null): RewardClaim | null {
  if (!raw || raw.length > 512) return null;
  let eventKey: unknown, source: unknown, claimIndex: unknown, ref: unknown;
  const trimmed = raw.trim();
  if (trimmed.startsWith("{")) {
    try {
      const o = JSON.parse(trimmed) as Record<string, unknown>;
      eventKey = o.event_key;
      source = o.source;
      claimIndex = o.claim_index;
      ref = o.reference_event_key ?? o.ref;
    } catch {
      return null;
    }
  } else {
    [eventKey, source, claimIndex, ref] = trimmed.split("|");
  }
  if (typeof eventKey !== "string" || !UUID_RE.test(eventKey)) return null;
  if (typeof source !== "string" || !REWARDED_SOURCES.has(source)) return null;
  let index: number | null = null;
  if (claimIndex !== undefined && claimIndex !== null && claimIndex !== "") {
    index = Number(claimIndex);
    if (!Number.isInteger(index) || index < 1 || index > 3) return null;
  }
  let reference: string | null = null;
  if (ref !== undefined && ref !== null && ref !== "") {
    if (typeof ref !== "string" || !UUID_RE.test(ref)) return null;
    reference = ref.toLowerCase();
  }
  if (source === "double_coins" && !reference) return null;
  return {
    eventKey: eventKey.toLowerCase(),
    source,
    claimIndex: index,
    referenceEventKey: reference,
  };
}

export type ClaimRpc = (args: {
  p_user: string;
  p_event_key: string;
  p_source: string;
  p_ad_transaction_id: string;
  p_reference_event_key: string | null;
  p_claim_index: number | null;
}) => PromiseLike<{ data: unknown; error: { message?: string } | null }>;

export interface HandlerDeps {
  lookup: KeyLookup;
  /** Returns null when the server is not configured (no service key). */
  claim: () => ClaimRpc | null;
  now?: () => number;
  maxAgeMs?: number;
}

// Outcomes Google must not retry (the claim can never succeed later).
const TERMINAL_CODES = new Set([
  "economy_disabled",
  "legacy_review_required",
  "already_claimed",
  "claim_limit",
  "invalid_payload",
  "invalid_source",
  "profile_required",
  "unknown_user",
]);

function reply(status: number, body: Record<string, unknown>): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

export async function handleAdMobCallback(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  if (req.method !== "GET") return reply(405, { error: "method_not_allowed" });
  const url = new URL(req.url);
  if (url.search.length > 4096) return reply(400, { error: "invalid_payload" });

  let params: URLSearchParams | null;
  try {
    params = await verifySignedQuery(url.search, deps.lookup);
  } catch {
    return reply(503, { error: "verifier_keys_unavailable" });
  }
  if (!params) return reply(400, { error: "invalid_signature" });

  const now = (deps.now ?? Date.now)();
  const timestamp = Number(params.get("timestamp"));
  const maxAge = deps.maxAgeMs ?? 72 * 60 * 60 * 1000;
  if (
    !Number.isFinite(timestamp) || timestamp > now + 5 * 60 * 1000 ||
    timestamp < now - maxAge
  ) {
    return reply(200, { status: "rejected", reason: "stale_callback" });
  }

  const userId = params.get("user_id") ?? "";
  const customData = params.get("custom_data");
  // AdMob's "verify URL" console test sends a signed callback without them.
  if (!userId && !customData) {
    return reply(200, { status: "verified_no_claim" });
  }
  const claim = parseCustomData(customData);
  const transactionId = params.get("transaction_id") ?? "";
  if (!UUID_RE.test(userId) || !claim || !TRANSACTION_RE.test(transactionId)) {
    return reply(200, { status: "rejected", reason: "invalid_payload" });
  }

  const rpc = deps.claim();
  if (!rpc) return reply(503, { error: "server_not_configured" });
  const { data, error } = await rpc({
    p_user: userId.toLowerCase(),
    p_event_key: claim.eventKey,
    p_source: claim.source,
    p_ad_transaction_id: transactionId,
    p_reference_event_key: claim.referenceEventKey,
    p_claim_index: claim.claimIndex,
  });
  if (error) {
    const code = error.message && /^[a-z_]{3,40}$/.test(error.message)
      ? error.message
      : "internal_error";
    if (TERMINAL_CODES.has(code)) {
      return reply(200, { status: "rejected", reason: code });
    }
    return reply(500, { error: "internal_error" });
  }
  const status = data && typeof data === "object" && "status" in data
    ? String((data as { status: unknown }).status)
    : "unknown";
  return reply(200, { status });
}
