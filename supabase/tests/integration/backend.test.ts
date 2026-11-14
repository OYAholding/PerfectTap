// End-to-end tests against the LOCAL Supabase stack (never a hosted project).
//   ./supabase/tests/integration/run.sh
// Covers: anonymous auth, RLS/cross-user access, duel lifecycle, simultaneous
// joins, concurrent/duplicate score submission, Realtime delivery + isolation,
// reconnect reload, rate limiting, legacy Firebase claim, email link, deletion.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.118.0";
import { exportJWK, generateKeyPair, SignJWT } from "npm:jose@6.2.14";
import { assert, assertEquals } from "jsr:@std/assert@1.0.13";

const URL = Deno.env.get("SB_URL") ?? "http://127.0.0.1:55621";
const KEY = Deno.env.get("SB_PUBLISHABLE_KEY")!;
const FAKE_FIREBASE_PORT = 55699;
const PROJECT = "perfecttap-48a08";
if (!URL.includes("127.0.0.1") && !URL.includes("localhost")) throw new Error("integration tests are local-only");

// ---------- fake Firebase (JWKS + signInWithPassword) ----------
const { publicKey, privateKey } = await generateKeyPair("RS256");
const jwk = { ...(await exportJWK(publicKey)), kid: "test-key", alg: "RS256", use: "sig" };
const FIREBASE_PASSWORDS: Record<string, { uid: string; password: string }> = {
  "legacy@test.local": { uid: "fb_legacy_email", password: "secret123" },
};
const FIRESTORE_PLAYERS: Record<string, Record<string, unknown>> = {};
const FIRESTORE_FRIENDSHIPS: string[][] = [];
const FIRESTORE_DOWN = new Set<string>();
const PSQL_URL = "postgresql://postgres:postgres@127.0.0.1:55622/postgres";
function psql(sql: string): string {
  const out = new Deno.Command("psql", { args: [PSQL_URL, "-tAc", sql] }).outputSync();
  if (!out.success) throw new Error(new TextDecoder().decode(out.stderr));
  return new TextDecoder().decode(out.stdout).trim();
}
const fakeFirebase = Deno.serve({ port: FAKE_FIREBASE_PORT, hostname: "0.0.0.0", onListen() {} }, async (req) => {
  const u = new globalThis.URL(req.url);
  if (u.pathname === "/jwks") return Response.json({ keys: [jwk] });
  if (u.pathname === "/v1/accounts:signInWithPassword") {
    const b = await req.json();
    const acct = FIREBASE_PASSWORDS[b.email];
    if (acct && acct.password === b.password) return Response.json({ localId: acct.uid });
    return Response.json({ error: { message: "INVALID_PASSWORD" } }, { status: 400 });
  }
  // Fake Firestore REST (just-in-time claim): players/{uid} GET and friendships :runQuery.
  const docsPrefix = `/v1/projects/${PROJECT}/databases/(default)/documents`;
  const path = decodeURIComponent(u.pathname);
  if (path.startsWith(docsPrefix)) {
    if (!(req.headers.get("authorization") ?? "").startsWith("Bearer ey")) return new Response("unauth", { status: 401 });
    const rest = path.slice(docsPrefix.length);
    if (rest.startsWith("/players/")) {
      const uid = rest.slice("/players/".length);
      if (FIRESTORE_DOWN.has(uid)) return Response.json({ error: { code: 503 } }, { status: 503 });
      const doc = FIRESTORE_PLAYERS[uid];
      if (!doc) return Response.json({ error: { code: 404, status: "NOT_FOUND" } }, { status: 404 });
      return Response.json({ name: `projects/${PROJECT}/databases/(default)/documents/players/${uid}`, fields: toFsFields(doc) });
    }
    if (rest === ":runQuery") {
      const q = await req.json();
      const uid = q.structuredQuery?.where?.fieldFilter?.value?.stringValue;
      return Response.json(FIRESTORE_FRIENDSHIPS.filter((ids) => ids.includes(uid))
        .map((ids) => ({ document: { fields: toFsFields({ user_ids: ids, created_at: new Date() }) } })));
    }
  }
  return new Response("nf", { status: 404 });
});
// Firestore typed-value encoding (what the REST API returns).
function toFs(v: unknown): Record<string, unknown> {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toFs) } };
  return { mapValue: { fields: toFsFields(v as Record<string, unknown>) } };
}
function toFsFields(o: Record<string, unknown>) {
  return Object.fromEntries(Object.entries(o).map(([k, x]) => [k, toFs(x)]));
}

async function firebaseToken(uid: string, opts: { email?: string; issuer?: string; emailVerified?: boolean } = {}) {
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({ auth_time: now - 10, email: opts.email, email_verified: opts.emailVerified ?? false,
                             firebase: { sign_in_provider: opts.email ? "password" : "anonymous" } })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuer(opts.issuer ?? `https://securetoken.google.com/${PROJECT}`)
    .setAudience(PROJECT).setSubject(uid).setIssuedAt(now).setExpirationTime(now + 3600)
    .sign(privateKey);
}

// ---------- helpers ----------
function client(): SupabaseClient {
  return createClient(URL, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
}
async function anonUser(name?: string) {
  const c = client();
  const { data, error } = await c.auth.signInAnonymously();
  if (error) throw error;
  if (name) {
    const r = await c.rpc("save_profile", { p: { username: name, friend_code: name.slice(0, 6).toUpperCase().padEnd(6, "X"), coins: 1 } });
    if (r.error) throw r.error;
  }
  return { c, id: data.user!.id };
}
const rid = () => crypto.randomUUID().slice(0, 6);
async function fn(c: SupabaseClient, name: string, body: unknown) {
  const { data: s } = await c.auth.getSession();
  const res = await fetch(`${URL}/functions/v1/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: KEY, Authorization: `Bearer ${s.session?.access_token}` },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
// Local Mailpit (supabase start) — reads the OTP Supabase Auth emailed.
const MAILPIT = Deno.env.get("SB_MAILPIT_URL") ?? "http://127.0.0.1:55624";
async function latestCode(to: string): Promise<string | null> {
  for (let i = 0; i < 40; i++) {
    const list = await (await fetch(`${MAILPIT}/api/v1/search?query=${encodeURIComponent("to:" + to)}`)).json();
    const id = list.messages?.[0]?.ID;
    if (id) {
      const msg = await (await fetch(`${MAILPIT}/api/v1/message/${id}`)).json();
      const m = String(msg.Text ?? msg.HTML ?? "").match(/\b(\d{6})\b/);
      if (m) return m[1];
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  return null;
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function waitFor(pred: () => boolean, ms = 8000) {
  const t = Date.now();
  while (!pred()) { if (Date.now() - t > ms) return false; await sleep(50); }
  return true;
}

const opts = { sanitizeOps: false, sanitizeResources: false };

// A fresh stack attaches the Realtime WAL listener lazily: SUBSCRIBED can arrive
// before change events flow. Warm it up once so timing-sensitive tests are stable.
Deno.test({ name: "realtime warm-up (first change event delivered)", ...opts, fn: async () => {
  const u = await anonUser("W" + rid());
  const { data: s } = await u.c.auth.getSession();
  u.c.realtime.setAuth(s.session!.access_token);
  let got = false;
  const ch = await new Promise<any>((resolve) => {
    const c = u.c.channel("warmup:" + rid())
      .on("postgres_changes", { event: "*", schema: "public", table: "duels", filter: `host_id=eq.${u.id}` }, () => { got = true; })
      .subscribe((st) => { if (st === "SUBSCRIBED") resolve(c); });
  });
  for (let i = 0; i < 6 && !got; i++) {
    await u.c.rpc("create_duel", { p_mode: "duel" });
    await waitFor(() => got, 5000);
  }
  await u.c.removeChannel(ch);
  assert(got, "Realtime delivered a change event within 30s");
}});

Deno.test({ name: "anonymous auth + profile privacy", ...opts, fn: async () => {
  const a = await anonUser("Alice" + rid());
  const b = await anonUser("Bob" + rid());
  const mine = await a.c.rpc("get_my_profile");
  assertEquals(mine.data.coins, 1);
  const theirs = await b.c.rpc("get_player_profiles", { p_ids: [a.id] });
  assertEquals(theirs.data.length, 1);
  assertEquals(theirs.data[0].coins, undefined, "coins must not leak to other players");
  // direct writes are refused
  const w = await b.c.from("profiles").update({ level: 999 }).eq("id", a.id);
  assert(w.error, "direct update must fail");
  const anon = client();
  const r = await anon.rpc("get_my_profile");
  assert(r.error, "anon key without session cannot call RPCs");
}});

Deno.test({ name: "simultaneous joins: exactly one guest wins", ...opts, fn: async () => {
  const host = await anonUser("Host" + rid());
  const joiners = await Promise.all([1, 2, 3, 4].map(() => anonUser("J" + rid())));
  const { data } = await host.c.rpc("create_duel", { p_mode: "duel" });
  const code = data[0].code;
  const results = await Promise.all(joiners.map((j) => j.c.rpc("join_duel", { p_code: code })));
  for (const r of results) assert(!r.error, r.error?.message);
  const winners = results.filter((r) => r.data.length === 1);
  assertEquals(winners.length, 1, "exactly one join succeeds; the others get no duel back");
}});

Deno.test({ name: "duel: realtime delivery, isolation, concurrent + duplicate submits", ...opts, fn: async () => {
  const host = await anonUser("H" + rid());
  const guest = await anonUser("G" + rid());
  const outsider = await anonUser("O" + rid());
  const { data } = await host.c.rpc("create_duel", { p_mode: "classic" });
  const duelId = data[0].duel_id, code = data[0].code;

  const hostEvents: any[] = [], outsiderEvents: any[] = [];
  const subscribe = (c: SupabaseClient, sink: any[]) => new Promise<any>((resolve) => {
    const ch = c.channel(`duel:${duelId}:${rid()}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "duels", filter: `id=eq.${duelId}` },
        (p) => sink.push(p.new))
      .subscribe((s) => { if (s === "SUBSCRIBED") resolve(ch); });
  });
  for (const u of [host, outsider]) {
    const { data: s } = await u.c.auth.getSession();
    u.c.realtime.setAuth(s.session!.access_token);
  }
  const hostCh = await subscribe(host.c, hostEvents);
  const outCh = await subscribe(outsider.c, outsiderEvents);
  // SUBSCRIBED can precede the WAL listener being attached on a cold stack; the
  // iOS client covers this window by reloading authoritative state after subscribe.
  await sleep(2500);

  const j = await guest.c.rpc("join_duel", { p_code: code });
  assert(!j.error, j.error?.message);
  assert(await waitFor(() => hostEvents.some((e) => e.status === "in_progress")), "host sees the join live");

  const hs = (await host.c.rpc("start_game_session", { p_mode: "classic", p_duel_id: duelId })).data;
  const gs = (await guest.c.rpc("start_game_session", { p_mode: "classic", p_duel_id: duelId })).data;
  assert(hs && gs);
  await sleep(4500); // sessions need some real elapsed time for the tap-rate bound
  const submit = (u: typeof host, s: string, score: number) =>
    u.c.rpc("submit_duel_score", { p_duel_id: duelId, p_session_id: s, p_score: score, p_max_combo: 5, p_taps: 10, p_perfects: 5 });
  // concurrent: both players + 3 duplicate host retries at once
  const res = await Promise.all([submit(host, hs, 900), submit(guest, gs, 700), submit(host, hs, 999), submit(host, hs, 999), submit(host, hs, 999)]);
  for (const r of res) assert(!r.error, r.error?.message);
  const { data: final } = await host.c.from("duels").select("*").eq("id", duelId).single();
  assertEquals(final.status, "completed");
  // Exactly one of the 4 racing host submissions is stored; the rest are reported as duplicates.
  const hostResults = [res[0], res[2], res[3], res[4]].map((r) => r.data);
  assertEquals(hostResults.filter((d) => !d.duplicate).length, 1, "exactly one host submission applied");
  assert([900, 999].includes(final.host_score), "stored host score comes from one submission");
  assertEquals(final.guest_score, 700);
  assert(await waitFor(() => hostEvents.some((e) => e.status === "completed")), "host sees completion live");
  assertEquals(outsiderEvents.length, 0, "outsider receives no events for someone else's duel");

  // reconnect: a fresh client reloads authoritative state
  const reread = await guest.c.from("duels").select("status,host_score,guest_score").eq("id", duelId).single();
  assertEquals(reread.data, { status: "completed", host_score: final.host_score, guest_score: 700 });
  // outsider cannot read or write it
  assertEquals((await outsider.c.from("duels").select("*").eq("id", duelId)).data?.length, 0);
  assertEquals((await submit(outsider, hs, 1)).error?.message, "duel_not_found");
  await host.c.removeChannel(hostCh); await outsider.c.removeChannel(outCh);
}});

Deno.test({ name: "duel score without a session (fresh connection) is accepted unverified", ...opts, fn: async () => {
  const host = await anonUser("NH" + rid());
  const guest = await anonUser("NG" + rid());
  const { data } = await host.c.rpc("create_duel", { p_mode: "duel" });
  await guest.c.rpc("join_duel", { p_code: data[0].code });
  const r = await guest.c.rpc("submit_duel_score", { p_duel_id: data[0].duel_id, p_session_id: null,
    p_score: 200, p_max_combo: 2, p_taps: 5, p_perfects: 2 });
  assert(!r.error, r.error?.message);
  assertEquals(r.data.accepted, true);
  const { data: d } = await guest.c.from("duels").select("guest_score,guest_verified").eq("id", data[0].duel_id).single();
  assertEquals(d, { guest_score: 200, guest_verified: false });
}});

Deno.test({ name: "rate limiting on join attempts", ...opts, fn: async () => {
  const u = await anonUser("R" + rid());
  let limited = false;
  for (let i = 0; i < 12; i++) {
    const r = await u.c.rpc("join_duel", { p_code: "ZZZZZZ" });
    if (r.error?.message === "rate_limited") limited = true;
  }
  assert(limited, "brute-forcing duel codes gets rate limited");
}});

Deno.test({ name: "friend → invitation → accept flow + realtime invite delivery", ...opts, fn: async () => {
  const a = await anonUser("FA" + rid());
  const b = await anonUser("FB" + rid());
  const bCode = (await b.c.rpc("get_my_profile")).data.friend_code;
  const req = await a.c.rpc("send_friend_request", { p_friend_code: bCode });
  assert(!req.error, req.error?.message);
  assert(!(await b.c.rpc("respond_friend_request", { p_request_id: req.data, p_accept: true })).error);

  const got: any[] = [];
  const { data: s } = await b.c.auth.getSession();
  b.c.realtime.setAuth(s.session!.access_token);
  await new Promise<void>((resolve) => b.c.channel("inv:" + rid())
    .on("postgres_changes", { event: "*", schema: "public", table: "duel_invitations", filter: `to_uid=eq.${b.id}` },
      (p) => got.push(p.new)).subscribe((st) => { if (st === "SUBSCRIBED") resolve(); }));
  await sleep(500);
  const inv = await a.c.rpc("send_duel_invitation", { p_to_uid: b.id, p_mode: "rush" });
  assert(!inv.error, inv.error?.message);
  assert(await waitFor(() => got.length > 0), "invitee notified in realtime");
  const acc = await b.c.rpc("accept_duel_invitation", { p_invitation_id: inv.data.id });
  assertEquals(acc.data, inv.data.duel_id);
}});

Deno.test({ name: "legacy Firebase claim, email link, deletion", ...opts, fn: async () => {
  // Fixture rows were ingested by run.sh (legacy.raw_docs → legacy.ingest()).
  const anonFb = await anonUser();
  const bad = await fn(anonFb.c, "claim-legacy-account", { firebaseIdToken: await firebaseToken("fb_legacy_anon", { issuer: "https://evil.example" }) });
  assertEquals(bad.status, 401, "token from wrong issuer rejected");
  // Deliberately unsigned fake token (test fixture, not a credential). gitleaks:allow
  const forged = await fn(anonFb.c, "claim-legacy-account", { firebaseIdToken: "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0." }); // gitleaks:allow
  assertEquals(forged.status, 401, "unsigned token rejected");

  const ok = await fn(anonFb.c, "claim-legacy-account", { firebaseIdToken: await firebaseToken("fb_legacy_anon") });
  assertEquals(ok.status, 200, JSON.stringify(ok.body));
  assertEquals(ok.body.status, "claimed");
  const prof = (await anonFb.c.rpc("get_my_profile")).data;
  assertEquals(prof.username, "LegacyAnon");
  assertEquals(prof.coins, 4321);
  const again = await fn(anonFb.c, "claim-legacy-account", { firebaseIdToken: await firebaseToken("fb_legacy_anon") });
  assertEquals(again.body.status, "already_claimed", "claim is idempotent");
  const thief = await anonUser();
  const steal = await fn(thief.c, "claim-legacy-account", { firebaseIdToken: await firebaseToken("fb_legacy_anon") });
  assertEquals(steal.status, 409, "second device can't take an already-claimed anonymous account");

  // email player: claim with password → can later sign in on a new device
  const emailUser = await anonUser();
  const tok = await firebaseToken("fb_legacy_email", { email: "legacy@test.local", emailVerified: true });
  const wrongPw = await fn(emailUser.c, "claim-legacy-account", { firebaseIdToken: tok, password: "nope-nope" });
  assertEquals(wrongPw.status, 401);
  const claimed = await fn(emailUser.c, "claim-legacy-account", { firebaseIdToken: tok, password: "secret123" });
  assertEquals(claimed.body.status, "claimed", JSON.stringify(claimed.body));
  assertEquals(claimed.body.friendshipsRestored, 1, "friendship with the already-migrated friend restored");
  assert(claimed.body.passwordSet);
  const fresh = client();
  const si = await fresh.auth.signInWithPassword({ email: "legacy@test.local", password: "secret123" });
  assert(!si.error, si.error?.message);
  assertEquals(si.data.user!.id, emailUser.id, "same Supabase account on a new device");

  // Firebase email that was never verified: progress moves, the email login does NOT.
  FIREBASE_PASSWORDS["unverified@test.local"] = { uid: "fb_unverified", password: "secret123" };
  const unv = await anonUser();
  const unvRes = await fn(unv.c, "claim-legacy-account", {
    firebaseIdToken: await firebaseToken("fb_unverified", { email: "unverified@test.local" }), password: "secret123" });
  assertEquals(unvRes.status, 200, JSON.stringify(unvRes.body));
  assertEquals(unvRes.body.emailLinked, false, "unverified email is not attached");
  assert((await client().auth.signInWithPassword({ email: "unverified@test.local", password: "secret123" })).error,
    "no login exists for an unverified email");

  // Cloud Backup: email is attached only after the emailed OTP is entered.
  const linker = await anonUser("Link" + rid());
  const em = `p${rid()}@test.local`;
  const upd = await linker.c.auth.updateUser({ email: em });
  assert(!upd.error, upd.error?.message);
  assert((await client().auth.signInWithPassword({ email: em, password: "hunter22" })).error, "no login before verification");
  const code = await latestCode(em);
  assert(code, "verification code emailed");
  const wrong = await linker.c.auth.verifyOtp({ email: em, token: code === "000000" ? "111111" : "000000", type: "email_change" });
  assert(wrong.error, "wrong code rejected");
  const ver = await linker.c.auth.verifyOtp({ email: em, token: code!, type: "email_change" });
  assert(!ver.error, ver.error?.message);
  assert(!(await linker.c.auth.updateUser({ password: "hunter22" })).error);
  const relogin = await client().auth.signInWithPassword({ email: em, password: "hunter22" });
  assert(!relogin.error, relogin.error?.message);
  assertEquals(relogin.data.user!.id, linker.id, "same account after verified link");
  // Someone else can't take a verified address.
  const other = await anonUser();
  const steal2 = await other.c.auth.updateUser({ email: em });
  assert(steal2.error, "email already in use");

  // deletion purges migrated data and blocks re-claim
  assertEquals((await fn(anonFb.c, "delete-account", {})).body.status, "deleted");
  const reclaim = await anonUser();
  const after = await fn(reclaim.c, "claim-legacy-account", { firebaseIdToken: await firebaseToken("fb_legacy_anon") });
  assertEquals(after.body.status, "account_deleted");
  // re-running the import must not resurrect a deleted player
  const reingest = new Deno.Command("psql", { args: ["postgresql://postgres:postgres@127.0.0.1:55622/postgres", "-tAc",
    "select legacy.ingest(); select count(*) from legacy.players where firebase_uid='fb_legacy_anon';"] }).outputSync();
  assert(new TextDecoder().decode(reingest.stdout).trim().endsWith("0"), "deleted player not re-imported");
}});

Deno.test({ name: "just-in-time claim: latest Firestore data, no overwrite, tombstones, fallback", ...opts, fn: async () => {
  const claim = async (c: SupabaseClient, uid: string) => await fn(c, "claim-legacy-account", { firebaseIdToken: await firebaseToken(uid) });
  const me = async (c: SupabaseClient) => (await c.rpc("get_my_profile")).data;

  // 1. Snapshot is stale (coins 10); Firestore has newer progress → the claim uses Firestore.
  FIRESTORE_PLAYERS["fb_jit_stale"] = { uid: "fb_jit_stale", username: "JitStale", friend_code: "JITST1", coins: 999,
    level: 9, best_classic: 7000, last_login: new Date("2026-11-13T10:00:00Z") };
  const a = await anonUser();
  const ra = await claim(a.c, "fb_jit_stale");
  assertEquals(ra.body.status, "claimed", JSON.stringify(ra.body));
  assertEquals((await me(a.c)).coins, 999, "fresh Firestore coins, not the stale snapshot");
  assertEquals((await me(a.c)).level, 9);

  // 2. Already migrated progress is never overwritten by a later Firestore read or re-import.
  const p = await me(a.c);
  assert(!(await a.c.rpc("save_profile", { p: { ...p, coins: 1500 } })).error);
  FIRESTORE_PLAYERS["fb_jit_stale"].coins = 5;
  assertEquals((await claim(a.c, "fb_jit_stale")).body.status, "already_claimed");
  psql("select legacy.ingest()");
  assertEquals((await me(a.c)).coins, 1500, "progress made after migration is kept");
  const thief = await anonUser();
  assertEquals((await claim(thief.c, "fb_jit_stale")).status, 409, "ownership stays with the first device");

  // 3. Player who started on 1.0 AFTER the last snapshot (not in legacy at all) still migrates.
  FIRESTORE_PLAYERS["fb_jit_new"] = { uid: "fb_jit_new", username: "JitNew", friend_code: "JITNW1", coins: 77, level: 3 };
  const b = await anonUser();
  const rb = await claim(b.c, "fb_jit_new");
  assertEquals(rb.body.status, "claimed", JSON.stringify(rb.body));
  assertEquals((await me(b.c)).username, "JitNew");

  // 4. Friendships Firestore confirms: canonical doc + mutual players.friends mirror.
  FIRESTORE_PLAYERS["fb_jit_c"] = { uid: "fb_jit_c", username: "JitC", friend_code: "JITC01", coins: 1, friends: ["fb_jit_b"] };
  const c = await anonUser();
  assertEquals((await claim(c.c, "fb_jit_c")).body.status, "claimed");
  FIRESTORE_PLAYERS["fb_jit_b"] = { uid: "fb_jit_b", username: "JitB", friend_code: "JITB01", coins: 2, friends: ["fb_jit_c"] };
  FIRESTORE_FRIENDSHIPS.push(["fb_jit_new", "fb_jit_b"]);
  const d = await anonUser();
  const rd = await claim(d.c, "fb_jit_b");
  assertEquals(rd.body.friendshipsRestored, 2, JSON.stringify(rd.body));

  // 5. Firestore unreachable → falls back to the snapshot (fixture coins 10).
  FIRESTORE_DOWN.add("fb_jit_down");
  const e = await anonUser();
  const re = await claim(e.c, "fb_jit_down");
  assertEquals(re.body.status, "claimed", JSON.stringify(re.body));
  assertEquals((await me(e.c)).coins, 10, "snapshot used when Firestore can't be read");

  // 6. A document whose uid doesn't match the token is ignored.
  FIRESTORE_PLAYERS["fb_jit_mismatch"] = { uid: "someone_else", username: "Mismatch", coins: 100000 };
  const f = await anonUser();
  assertEquals((await claim(f.c, "fb_jit_mismatch")).body.status, "no_legacy_data");

  // 7. Deleted account: tombstone wins even though Firestore still has the document.
  assertEquals((await fn(b.c, "delete-account", {})).body.status, "deleted");
  const g = await anonUser();
  assertEquals((await claim(g.c, "fb_jit_new")).body.status, "account_deleted");
  assertEquals(psql("select count(*) from legacy.players where firebase_uid='fb_jit_new'"), "0", "not resurrected");

  // 8. Blocked legacy username → player is asked to choose a new name; progress still moves.
  FIRESTORE_PLAYERS["fb_jit_rude"] = { uid: "fb_jit_rude", username: "Sh1tLord", friend_code: "JITRD1", coins: 42 };
  const h = await anonUser();
  const rh = await claim(h.c, "fb_jit_rude");
  assertEquals(rh.body.usernameConflict, true, JSON.stringify(rh.body));
  assertEquals((await me(h.c)).username, "");
  assertEquals((await me(h.c)).coins, 42);
}});

Deno.test({ name: "username moderation: blocklist, neutral rename, sync never breaks", ...opts, fn: async () => {
  const u = await anonUser();
  const avail = async (n: string) => (await u.c.rpc("is_username_available", { p_username: n })).data;
  for (const bad of ["FuckYou", "sh1t_head", "B1TCH", "Admin", "perfect_tap", "fuuuuck"]) assertEquals(await avail(bad), false, bad);
  for (const ok of ["Grapefruit", "class_pass", "Scott99", "Hancock", "Therapist"]) assertEquals(await avail(ok), true, ok);

  // An old/offline client saves a blocked name without asking first → neutral name, no failure.
  const bad = await anonUser();
  assert(!(await bad.c.rpc("save_profile", { p: { username: "FuckYou" + rid(), friend_code: "BAD" + rid().slice(0, 3).toUpperCase(), coins: 5 } })).error);
  const prof = (await bad.c.rpc("get_my_profile")).data;
  assert(String(prof.username).startsWith("Player_"), prof.username);
  // The app keeps sending its cached name: saves keep working and keep the neutral name.
  const again = await bad.c.rpc("save_profile", { p: { ...prof, username: "FuckYou1", coins: 9 } });
  assert(!again.error, again.error?.message);
  assertEquals((await bad.c.rpc("get_my_profile")).data.coins, 9);
  assert(String((await bad.c.rpc("get_my_profile")).data.username).startsWith("Player_"));

  // Report → moderator renames the player everywhere; progress and sync are unaffected.
  const name = "Rude" + rid();
  const r = await anonUser(name);
  const neu = psql(`select private.moderate_username('${r.id}', 'test report')`);
  assert(neu.startsWith("Player_"), neu);
  const rp = (await r.c.rpc("get_my_profile")).data;
  assertEquals(rp.username, neu);
  assert(!(await r.c.rpc("save_profile", { p: { ...rp, username: name, coins: 3 } })).error, "cached old name ignored");
  assertEquals((await r.c.rpc("get_my_profile")).data.username, neu);
  assertEquals(psql(`select count(*) from private.moderation_log where user_id='${r.id}'`), "1");

  // A normal (not moderated) player still can't change a chosen name.
  const n = await anonUser("Keep" + rid());
  const np = (await n.c.rpc("get_my_profile")).data;
  const ch = await n.c.rpc("save_profile", { p: { ...np, username: "Other" + rid() } });
  assertEquals(ch.error?.message, "username_immutable");

  // Reports: stored once per pair, can't report yourself.
  assert(!(await u.c.rpc("report_player", { p_reported: r.id })).error);
  assert(!(await u.c.rpc("report_player", { p_reported: r.id })).error, "duplicate report is a no-op");
  assertEquals(psql(`select count(*) from private.player_reports where reported_id='${r.id}'`), "1");
  assert((await u.c.rpc("report_player", { p_reported: u.id })).error, "self-report rejected");

  // Not callable through the API.
  assert((await u.c.rpc("moderate_username", { p_user: u.id })).error);
  assert((await u.c.rpc("claim_legacy_profile_fresh", { p_user: u.id, p_firebase_uid: "x" })).error);
}});

addEventListener("unload", () => fakeFirebase.shutdown());
