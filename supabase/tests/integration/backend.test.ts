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
const fakeFirebase = Deno.serve({ port: FAKE_FIREBASE_PORT, hostname: "0.0.0.0", onListen() {} }, async (req) => {
  const u = new globalThis.URL(req.url);
  if (u.pathname === "/jwks") return Response.json({ keys: [jwk] });
  if (u.pathname === "/v1/accounts:signInWithPassword") {
    const b = await req.json();
    const acct = FIREBASE_PASSWORDS[b.email];
    if (acct && acct.password === b.password) return Response.json({ localId: acct.uid });
    return Response.json({ error: { message: "INVALID_PASSWORD" } }, { status: 400 });
  }
  return new Response("nf", { status: 404 });
});

async function firebaseToken(uid: string, opts: { email?: string; issuer?: string } = {}) {
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({ auth_time: now - 10, email: opts.email, firebase: { sign_in_provider: opts.email ? "password" : "anonymous" } })
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
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function waitFor(pred: () => boolean, ms = 8000) {
  const t = Date.now();
  while (!pred()) { if (Date.now() - t > ms) return false; await sleep(50); }
  return true;
}

const opts = { sanitizeOps: false, sanitizeResources: false };

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
  const tok = await firebaseToken("fb_legacy_email", { email: "legacy@test.local" });
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

  // link-email for a brand-new anonymous player
  const linker = await anonUser("Link" + rid());
  const em = `p${rid()}@test.local`;
  assertEquals((await fn(linker.c, "link-email", { email: em, password: "hunter22" })).body.status, "linked");
  const other = await anonUser();
  assertEquals((await fn(other.c, "link-email", { email: em, password: "hunter22" })).status, 409, "email can't be reused");
  assert(!(await client().auth.signInWithPassword({ email: em, password: "hunter22" })).error);

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

addEventListener("unload", () => fakeFirebase.shutdown());
