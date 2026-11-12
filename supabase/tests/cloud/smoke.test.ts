// Smoke test against the HOSTED PerfectTap project (Frankfurt) with the public
// publishable key only — exactly what the iOS app has. Every user it creates
// deletes itself through the delete-account Edge Function at the end.
//   SB_URL=https://<ref>.supabase.co SB_PUBLISHABLE_KEY=sb_publishable_… \
//     deno test -A --config supabase/tests/integration/deno.json supabase/tests/cloud/smoke.test.ts
// Uses ~5 anonymous sign-ins (Auth limit: 30/hour/IP).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.118.0";
import { assert, assertEquals } from "jsr:@std/assert@1.0.13";

const URL = Deno.env.get("SB_URL")!;
const KEY = Deno.env.get("SB_PUBLISHABLE_KEY")!;
if (!URL?.startsWith("https://") || !KEY?.startsWith("sb_publishable_")) throw new Error("SB_URL / SB_PUBLISHABLE_KEY required");

type U = { c: SupabaseClient; id: string; token: string };
const created: U[] = [];
const rid = () => crypto.randomUUID().replaceAll("-", "").slice(0, 6);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function waitFor(pred: () => boolean, ms = 10000) {
  const t = Date.now();
  while (!pred()) { if (Date.now() - t > ms) return false; await sleep(100); }
  return true;
}
async function player(name: string): Promise<U> {
  const c = createClient(URL, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await c.auth.signInAnonymously();
  if (error) throw error;
  const u = { c, id: data.user!.id, token: data.session!.access_token };
  created.push(u);
  c.realtime.setAuth(u.token);
  const r = await c.rpc("save_profile", { p: { username: name, friend_code: ("C" + rid()).toUpperCase(), coins: 7 } });
  if (r.error) throw new Error("save_profile: " + r.error.message);
  return u;
}
async function fn(u: U, name: string, body: unknown = {}) {
  const res = await fetch(`${URL}/functions/v1/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: KEY, Authorization: `Bearer ${u.token}` },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
const opts = { sanitizeOps: false, sanitizeResources: false };

Deno.test({ name: "cloud: full duel lifecycle, realtime, concurrency, RLS", ...opts, fn: async () => {
  const host = await player("CH" + rid());
  const guest = await player("CG" + rid());
  const out1 = await player("CO" + rid());
  const out2 = await player("CP" + rid());

  // profile privacy
  const pub = await out1.c.rpc("get_player_profiles", { p_ids: [host.id] });
  assertEquals(pub.data?.[0]?.coins, undefined, "coins hidden from other players");
  assertEquals((await host.c.rpc("get_my_profile")).data.coins, 7);
  assert((await out1.c.from("profiles").update({ level: 99 }).eq("id", host.id)).error, "direct write refused");
  assert((await createClient(URL, KEY).rpc("get_my_profile")).error, "anon key alone can't call RPCs");

  const { data: d } = await host.c.rpc("create_duel", { p_mode: "classic" });
  const duelId = d[0].duel_id, code = d[0].code;

  const hostEvents: any[] = [], outEvents: any[] = [];
  const sub = (u: U, sink: any[]) => new Promise<any>((res, rej) => {
    const ch = u.c.channel(`smoke-${duelId}-${rid()}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "duels", filter: `id=eq.${duelId}` }, (p) => sink.push(p.new))
      .subscribe((s, e) => { if (s === "SUBSCRIBED") res(ch); if (s === "CHANNEL_ERROR") rej(e); });
  });
  const hc = await sub(host, hostEvents);
  const oc = await sub(out1, outEvents);
  await sleep(2500);

  // 3 players race for the guest slot: exactly one wins
  const joins = await Promise.all([guest, out1, out2].map((u) => u.c.rpc("join_duel", { p_code: code })));
  for (const j of joins) assert(!j.error, j.error?.message);
  const winners = joins.map((j, i) => (j.data.length === 1 ? i : -1)).filter((i) => i >= 0);
  assertEquals(winners.length, 1, "exactly one join wins");
  const realGuest = [guest, out1, out2][winners[0]];
  assert(await waitFor(() => hostEvents.some((e) => e.status === "in_progress")), "host notified of join in realtime");

  const hs = (await host.c.rpc("start_game_session", { p_mode: "classic", p_duel_id: duelId })).data;
  const gs = (await realGuest.c.rpc("start_game_session", { p_mode: "classic", p_duel_id: duelId })).data;
  assert(hs && gs, "server-timed sessions issued");
  await sleep(4500);
  const submit = (u: U, s: string, score: number) => u.c.rpc("submit_duel_score",
    { p_duel_id: duelId, p_session_id: s, p_score: score, p_max_combo: 4, p_taps: 10, p_perfects: 4 });
  const res = await Promise.all([submit(host, hs, 800), submit(realGuest, gs, 600), submit(host, hs, 999), submit(host, hs, 999)]);
  for (const r of res) assert(!r.error, r.error?.message);
  assertEquals([res[0], res[2], res[3]].filter((r) => !r.data.duplicate).length, 1, "duplicates don't double-apply");

  const { data: finRow } = await host.c.from("duels").select("status,host_score,guest_score,host_verified,guest_verified").eq("id", duelId).single();
  const fin = finRow!;
  assertEquals(fin.status, "completed");
  assertEquals(fin.guest_score, 600);
  assert(fin.host_verified && fin.guest_verified, "both scores verified by server time");
  assert(await waitFor(() => hostEvents.some((e) => e.status === "completed")), "completion delivered in realtime");
  const outsider = realGuest === out1 ? out2 : out1;
  assertEquals((await outsider.c.from("duels").select("id").eq("id", duelId)).data?.length, 0, "outsider can't read duel");
  if (outsider === out1) assertEquals(outEvents.length, 0, "outsider got no realtime events");
  assertEquals((await submit(outsider, hs, 1)).error?.message, "duel_not_found", "outsider can't submit");
  assertEquals((await submit(host, hs, 5)).data.duplicate, true, "completed duel immutable");

  // impossible ranked score rejected
  const rs = (await host.c.rpc("start_game_session", { p_mode: "classic" })).data;
  const bad = await host.c.rpc("submit_score", { p_session_id: rs, p_mode: "classic", p_score: 999999, p_max_combo: 9, p_taps: 9, p_perfects: 9 });
  assertEquals(bad.data.accepted, false);

  await host.c.removeChannel(hc); await out1.c.removeChannel(oc);
}});

Deno.test({ name: "cloud: friends + invitation + Edge Function auth", ...opts, fn: async () => {
  const a = created[0], b = created[1];
  const bCode = (await b.c.rpc("get_my_profile")).data.friend_code;
  const req = await a.c.rpc("send_friend_request", { p_friend_code: bCode });
  assert(!req.error, req.error?.message);
  assert(!(await b.c.rpc("respond_friend_request", { p_request_id: req.data, p_accept: true })).error);
  const inv = await a.c.rpc("send_duel_invitation", { p_to_uid: b.id, p_mode: "rush" });
  assert(!inv.error, inv.error?.message);
  assertEquals((await b.c.rpc("accept_duel_invitation", { p_invitation_id: inv.data.id })).data, inv.data.duel_id);

  const forged = await fn(a, "claim-legacy-account", { firebaseIdToken: "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0." }); // gitleaks:allow
  assertEquals(forged.status, 401, "unsigned Firebase token rejected in the cloud");
  const noAuth = await fetch(`${URL}/functions/v1/delete-account`, { method: "POST", headers: { apikey: KEY } });
  assertEquals(noAuth.status, 401, "delete-account requires a user JWT");
}});

Deno.test({ name: "cloud: cleanup — every test user deletes itself", ...opts, fn: async () => {
  for (const u of created) {
    const r = await fn(u, "delete-account");
    assertEquals(r.status, 200, JSON.stringify(r.body));
  }
}});
