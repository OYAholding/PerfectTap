import { assert, assertEquals } from "jsr:@std/assert@1.0.13";
import {
  ADMOB_KEYS_URL,
  type ClaimRpc,
  derToP1363,
  handleAdMobCallback,
  importVerifierKey,
  type KeyLookup,
  makeGoogleKeyLookup,
  parseCustomData,
  verifySignedQuery,
} from "./admob.ts";

const KEY_ID = "3335741209";
const USER = "aaaaaaaa-0000-0000-0000-000000000001";
const EVENT = "bbbbbbbb-0000-4000-8000-000000000001";
const NOW = 1_795_000_000_000;

// ---------- local test key (never Google's) ----------
const pair = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
const spkiB64 = btoa(
  String.fromCharCode(
    ...new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey)),
  ),
);
const publicKey = await importVerifierKey(spkiB64);
const otherPair = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);

function derInt(bytes: Uint8Array): number[] {
  let i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  const v = Array.from(bytes.subarray(i));
  if (v[0] & 0x80) v.unshift(0);
  return [0x02, v.length, ...v];
}

function p1363ToDer(raw: Uint8Array): Uint8Array {
  const body = [...derInt(raw.subarray(0, 32)), ...derInt(raw.subarray(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(
    /\//g,
    "_",
  ).replace(/=+$/, "");
}

async function signQuery(
  message: string,
  key: CryptoKey = pair.privateKey,
  keyId = KEY_ID,
): Promise<string> {
  const raw = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(message),
    ),
  );
  return `${message}&signature=${b64url(p1363ToDer(raw))}&key_id=${keyId}`;
}

function baseMessage(over: Record<string, string> = {}): string {
  const p = new URLSearchParams({
    ad_network: "5450213213286189855",
    ad_unit: "1234567890",
    custom_data: JSON.stringify({ event_key: EVENT, source: "home_rewarded" }),
    reward_amount: "1",
    reward_item: "coins",
    timestamp: String(NOW - 1000),
    transaction_id: "123456789abcdef",
    user_id: USER,
    ...over,
  });
  return p.toString();
}

const lookup: KeyLookup = (id) =>
  Promise.resolve(id === KEY_ID ? publicKey : null);

function fakeClaim(
  reply: { data: unknown; error: { message?: string } | null },
) {
  const calls: Parameters<ClaimRpc>[0][] = [];
  const rpc: ClaimRpc = (args) => {
    calls.push(args);
    return Promise.resolve(reply);
  };
  return { rpc, calls };
}

function req(query: string, method = "GET"): Request {
  return new Request(`https://x.supabase.co/functions/v1/admob-ssv?${query}`, {
    method,
  });
}

// ---------- signature ----------
Deno.test("verifies a Google-style signed query", async () => {
  const params = await verifySignedQuery(
    await signQuery(baseMessage()),
    lookup,
  );
  assert(params);
  assertEquals(params.get("user_id"), USER);
});

Deno.test("rejects a tampered parameter", async () => {
  const signed = await signQuery(baseMessage());
  const tampered = signed.replace("reward_amount=1", "reward_amount=9");
  assertEquals(await verifySignedQuery(tampered, lookup), null);
});

Deno.test("rejects a signature from another key", async () => {
  const signed = await signQuery(baseMessage(), otherPair.privateKey);
  assertEquals(await verifySignedQuery(signed, lookup), null);
});

Deno.test("rejects unknown key ids and missing signatures", async () => {
  assertEquals(
    await verifySignedQuery(
      await signQuery(baseMessage(), pair.privateKey, "42"),
      lookup,
    ),
    null,
  );
  assertEquals(await verifySignedQuery(baseMessage(), lookup), null);
});

Deno.test("rejects parameters appended after the signature", async () => {
  const signed = await signQuery(baseMessage());
  assertEquals(
    await verifySignedQuery(`${signed}&user_id=${USER}`, lookup),
    null,
  );
});

Deno.test("DER conversion handles leading-zero integers", () => {
  const raw = new Uint8Array(64);
  raw[0] = 0x80; // r needs a 0x00 pad in DER
  raw[32] = 0x00;
  raw[33] = 0x01; // s is short in DER
  raw[63] = 0x05;
  assertEquals(derToP1363(p1363ToDer(raw)), raw);
  assertEquals(derToP1363(new Uint8Array([0x31, 0x00])), null);
});

// ---------- custom_data ----------
Deno.test("parses JSON and pipe custom_data", () => {
  assertEquals(
    parseCustomData(
      JSON.stringify({
        event_key: EVENT,
        source: "double_coins",
        claim_index: 1,
        reference_event_key: USER,
      }),
    ),
    {
      eventKey: EVENT,
      source: "double_coins",
      claimIndex: 1,
      referenceEventKey: USER,
    },
  );
  assertEquals(parseCustomData(`${EVENT}|revive|2`), {
    eventKey: EVENT,
    source: "revive",
    claimIndex: 2,
    referenceEventKey: null,
  });
  assertEquals(parseCustomData(`${EVENT}|double_coins|1`), null); // needs a reference
  assertEquals(parseCustomData(`${EVENT}|wheel|1`), null); // not an ad source
  assertEquals(parseCustomData(`not-a-uuid|revive|1`), null);
  assertEquals(parseCustomData(`${EVENT}|revive|7`), null);
});

// ---------- handler ----------
Deno.test("handler records a verified claim with server-side args", async () => {
  const { rpc, calls } = fakeClaim({
    data: { status: "applied", granted: 15 },
    error: null,
  });
  const res = await handleAdMobCallback(req(await signQuery(baseMessage())), {
    lookup,
    claim: () => rpc,
    now: () => NOW,
  });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "applied" });
  assertEquals(calls, [{
    p_user: USER,
    p_event_key: EVENT,
    p_source: "home_rewarded",
    p_ad_transaction_id: "123456789abcdef",
    p_reference_event_key: null,
    p_claim_index: null,
  }]);
});

Deno.test("handler refuses bad signatures without touching the database", async () => {
  const { rpc, calls } = fakeClaim({ data: null, error: null });
  const signed = await signQuery(baseMessage(), otherPair.privateKey);
  const res = await handleAdMobCallback(req(signed), {
    lookup,
    claim: () => rpc,
    now: () => NOW,
  });
  assertEquals(res.status, 400);
  assertEquals(calls.length, 0);
});

Deno.test("terminal database outcomes answer 200 so Google stops retrying", async () => {
  const { rpc } = fakeClaim({ data: null, error: { message: "claim_limit" } });
  const res = await handleAdMobCallback(req(await signQuery(baseMessage())), {
    lookup,
    claim: () => rpc,
    now: () => NOW,
  });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "rejected", reason: "claim_limit" });
});

Deno.test("transient failures answer 5xx and never leak details", async () => {
  const { rpc } = fakeClaim({
    data: null,
    error: { message: "connection refused at 10.0.0.1" },
  });
  const res = await handleAdMobCallback(req(await signQuery(baseMessage())), {
    lookup,
    claim: () => rpc,
    now: () => NOW,
  });
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: "internal_error" });
});

Deno.test("console verify-URL test and stale callbacks are not claimed", async () => {
  const { rpc, calls } = fakeClaim({ data: null, error: null });
  const probe = new URLSearchParams({
    ad_network: "1",
    ad_unit: "2",
    reward_amount: "1",
    reward_item: "coins",
    timestamp: String(NOW),
    transaction_id: "probe1",
  }).toString();
  const res = await handleAdMobCallback(req(await signQuery(probe)), {
    lookup,
    claim: () => rpc,
    now: () => NOW,
  });
  assertEquals(await res.json(), { status: "verified_no_claim" });
  const stale = await handleAdMobCallback(
    req(await signQuery(baseMessage({ timestamp: String(NOW - 4 * 86400e3) }))),
    { lookup, claim: () => rpc, now: () => NOW },
  );
  assertEquals(await stale.json(), {
    status: "rejected",
    reason: "stale_callback",
  });
  const post = await handleAdMobCallback(req("", "POST"), {
    lookup,
    claim: () => rpc,
  });
  assertEquals(post.status, 405);
  assertEquals(calls.length, 0);
});

// ---------- key cache ----------
Deno.test("verifier keys are fetched once, cached, and refetched for new ids", async () => {
  let fetches = 0;
  let clock = NOW;
  const fakeFetch = ((url: string) => {
    fetches++;
    assertEquals(url, ADMOB_KEYS_URL);
    return Promise.resolve(
      Response.json({
        keys: [{ keyId: Number(KEY_ID), base64: spkiB64, pem: "unused" }],
      }),
    );
  }) as unknown as typeof fetch;
  const cached = makeGoogleKeyLookup(
    fakeFetch,
    86_400_000,
    300_000,
    () => clock,
  );
  assert(await cached(KEY_ID));
  assert(await cached(KEY_ID));
  assertEquals(fetches, 1);
  assertEquals(await cached("999"), null); // within minRefetch: no refetch
  assertEquals(fetches, 1);
  clock += 301_000;
  assertEquals(await cached("999"), null); // unknown id after window: one refetch
  assertEquals(fetches, 2);
  clock += 86_400_001;
  assert(await cached(KEY_ID)); // TTL expiry
  assertEquals(fetches, 3);
});
