// Firestore security-rules tests for PerfectTap.
// Every "client:" test replays a write the iOS app (FirebaseService.swift) makes,
// with the same payload shape — these MUST pass or shipped clients break.
// Every "attack:" test is something a modified client could try.
//
// Run:  cd firestore-tests && npm install && npm test   (needs Java 21+ for the emulator)

import { test, before, after, beforeEach, describe } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection,
  serverTimestamp, Timestamp, runTransaction, arrayUnion,
} from 'firebase/firestore';

let env;
const ALICE = 'alice_uid', BOB = 'bob_uid', EVE = 'eve_uid';
const pairId = (a, b) => [a, b].sort().join('_');
const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// Admin seeding (bypasses rules).
async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

// Mirrors FirebaseService.encode(_:) for a typical profile.
function profilePayload(uid, overrides = {}) {
  return {
    uid, username: 'alice', username_lower: 'alice', avatar: 'default',
    coins: 29, level: 1, xp: 8,
    best_classic: 70, best_endless: 0, best_timed: 0, best_sudden: 0, best_combofrenzy: 0,
    friend_code: 'ABC123', friends: [], owned_items: ['theme_default'],
    equipped_theme: 'default', equipped_avatar: 'default', equipped_tapfx: 'fx_default',
    equipped_trail: '', equipped_badge: '',
    daily_reward_streak: 0, daily_reward_last_claim: '', active_challenge: '',
    season_xp: 5, season_tier: 0, season_premium: false, season_ad_progress: 0,
    season_claimed_tiers: [], quests_json: '', achievements: ['first_game'],
    completed_challenges: [], no_ads: false, revives_used_today: 0, last_revive_date: '',
    best_scores_extra: { best_rush: 300 }, best_rush: 300,
    score_history: [{ id: 'x', score: 70, date: '2026-11-04T19:05:00Z' }],
    stats: { totalGames: 1, duelWins: 0, duelLosses: 0, duelTies: 0,
             totalCoinsEarned: 4, perfectTaps: 0, highestCombo: 1 },
    boost: null,
    ...overrides,
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-perfecttap',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

// ───────────────────────── players ─────────────────────────
describe('players', () => {
  test('client: first save creates own profile (merge)', async () => {
    await assertSucceeds(setDoc(doc(db(ALICE), 'players', ALICE), profilePayload(ALICE), { merge: true }));
  });
  test('client: worst case — first save with EVERY field incl. all extra best scores', async () => {
    const extras = { best_precision: 1, best_chaos: 2, best_mirror: 3, best_invisiblezone: 4,
                     best_rush: 5, best_hardcorecombo: 6, best_tinywindow: 7, best_focus: 8 };
    await assertSucceeds(setDoc(doc(db(ALICE), 'players', ALICE), profilePayload(ALICE, {
      ...extras, best_scores_extra: extras, no_ads: true, season_premium: true,
      boost: { value: 1.5, used: false, games: 3 }, server_day_probe_ts: serverTimestamp(),
      friends: ['a', 'b', 'c'], owned_items: Array.from({ length: 40 }, (_, i) => `item_${i}`),
    }), { merge: true }));
  });
  test('client: worst case — every field changes on an existing doc', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE, { username: '', username_lower: '' }));
    const extras = { best_precision: 9, best_chaos: 9, best_mirror: 9, best_invisiblezone: 9,
                     best_rush: 9, best_hardcorecombo: 9, best_tinywindow: 9, best_focus: 9 };
    await assertSucceeds(setDoc(doc(db(ALICE), 'players', ALICE), profilePayload(ALICE, {
      ...extras, best_scores_extra: extras, coins: 999, level: 9, xp: 9, best_classic: 9,
      best_endless: 9, best_timed: 9, best_sudden: 9, best_combofrenzy: 9, season_xp: 9,
      season_tier: 9, no_ads: true, season_premium: true, avatar: 'x', friend_code: 'ZZ9',
      equipped_theme: 'fire', equipped_avatar: 'x', equipped_tapfx: 'x', equipped_trail: 'x',
      equipped_badge: 'x', daily_reward_streak: 3, daily_reward_last_claim: '2026-11-04',
      active_challenge: 'c1', season_ad_progress: 2, quests_json: '[]', revives_used_today: 1,
      last_revive_date: '2026-11-04', server_day_probe_ts: serverTimestamp(),
      stats: { totalGames: 9, duelWins: 1, duelLosses: 1, duelTies: 1, totalCoinsEarned: 9,
               perfectTaps: 9, highestCombo: 9 },
      boost: { value: 2, used: true, games: 0 },
    }), { merge: true }));
  });
  test('client: server-day probe before any profile exists', async () => {
    await assertSucceeds(setDoc(doc(db(ALICE), 'players', ALICE),
      { server_day_probe_ts: serverTimestamp() }, { merge: true }));
  });
  test('client: later save with progress', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertSucceeds(setDoc(doc(db(ALICE), 'players', ALICE),
      profilePayload(ALICE, { coins: 500, best_classic: 12000, level: 4 }), { merge: true }));
  });
  test('client: username chosen once on a nameless doc', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE, { username: '', username_lower: '' }));
    await assertSucceeds(setDoc(doc(db(ALICE), 'players', ALICE), profilePayload(ALICE), { merge: true }));
  });
  test('client: legacy unknown field already in doc does not block saves', async () => {
    await seed(`players/${ALICE}`, { ...profilePayload(ALICE), legacy_web_field: 1 });
    await assertSucceeds(setDoc(doc(db(ALICE), 'players', ALICE),
      profilePayload(ALICE, { coins: 31 }), { merge: true }));
  });
  test('client: any signed-in user can read profiles (leaderboard)', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertSucceeds(getDoc(doc(db(BOB), 'players', ALICE)));
  });
  test('client: owner deletes own doc (account deletion)', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertSucceeds(deleteDoc(doc(db(ALICE), 'players', ALICE)));
  });

  test('attack: unauthenticated read', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertFails(getDoc(doc(anon(), 'players', ALICE)));
  });
  test('attack: write someone else\'s profile', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertFails(updateDoc(doc(db(EVE), 'players', ALICE), { coins: 0 }));
  });
  test('attack: negative / non-integer / absurd coins', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    const ref = doc(db(ALICE), 'players', ALICE);
    await assertFails(updateDoc(ref, { coins: -5 }));
    await assertFails(updateDoc(ref, { coins: '999999' }));
    await assertFails(updateDoc(ref, { coins: 1e12 }));
  });
  test('attack: absurd best score', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertFails(updateDoc(doc(db(ALICE), 'players', ALICE), { best_classic: 2147483647 }));
  });
  test('attack: rename after username is set', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertFails(updateDoc(doc(db(ALICE), 'players', ALICE),
      { username: 'bob', username_lower: 'bob' }));
  });
  test('attack: username_lower out of sync (uniqueness bypass)', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE, { username: '', username_lower: '' }));
    await assertFails(updateDoc(doc(db(ALICE), 'players', ALICE),
      { username: 'Admin', username_lower: 'not_admin' }));
  });
  test('attack: invalid username characters', async () => {
    await assertFails(setDoc(doc(db(ALICE), 'players', ALICE),
      profilePayload(ALICE, { username: '<script>', username_lower: '<script>' })));
  });
  test('attack: forged server-day timestamp', async () => {
    await assertFails(setDoc(doc(db(ALICE), 'players', ALICE),
      { server_day_probe_ts: Timestamp.fromDate(new Date('2030-01-01')) }, { merge: true }));
  });
  test('attack: uid field pointing at another user', async () => {
    await assertFails(setDoc(doc(db(EVE), 'players', EVE), profilePayload(ALICE)));
  });
  test('attack: arbitrary new field', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertFails(updateDoc(doc(db(ALICE), 'players', ALICE), { is_admin: true }));
  });
  test('known gap (needs Cloud Functions): plausible fake coins still accepted', async () => {
    await seed(`players/${ALICE}`, profilePayload(ALICE));
    await assertSucceeds(updateDoc(doc(db(ALICE), 'players', ALICE), { coins: 50000 }));
  });
});

// ───────────────────────── leaderboard (unused) ─────────────────────────
describe('leaderboard', () => {
  test('attack: direct score injection', async () => {
    await assertFails(setDoc(doc(db(EVE), 'leaderboard', 'classic', 'scores', EVE), { score: 199999 }));
  });
});

// ───────────────────────── duels ─────────────────────────
const newDuel = (host) => ({
  code: 'K7QX2M', host_id: host, host_name: 'alice', host_avatar: 'default',
  mode: 'duel', status: 'waiting', created_at: serverTimestamp(),
});
async function seedDuel(id, extra = {}) {
  await seed(`duels/${id}`, { ...newDuel(ALICE), created_at: Timestamp.now(), ...extra });
}

describe('duels', () => {
  test('client: host creates duel (addDocument)', async () => {
    await assertSucceeds(addDoc(collection(db(ALICE), 'duels'), newDuel(ALICE)));
  });
  test('client: guest joins in a transaction', async () => {
    await seedDuel('d1');
    const f = db(BOB);
    const ref = doc(f, 'duels', 'd1');
    await assertSucceeds(runTransaction(f, async (tx) => {
      const snap = await tx.get(ref);
      if (snap.data().status !== 'waiting') throw new Error('joined');
      tx.update(ref, { guest_id: BOB, guest_name: 'bob', guest_avatar: 'default', status: 'in_progress' });
    }));
  });
  test('client: host submits score while still waiting (async duel)', async () => {
    await seedDuel('d1');
    await assertSucceeds(updateDoc(doc(db(ALICE), 'duels', 'd1'), { host_score: 4200, host_combo: 12 }));
  });
  test('client: guest submits after host and completes the duel', async () => {
    await seedDuel('d1', { guest_id: BOB, guest_name: 'bob', status: 'in_progress', host_score: 4200, host_combo: 12 });
    await assertSucceeds(updateDoc(doc(db(BOB), 'duels', 'd1'),
      { guest_score: 3900, guest_combo: 9, status: 'completed' }));
  });
  test('client: zero score is a valid finished score', async () => {
    await seedDuel('d1', { guest_id: BOB, status: 'in_progress' });
    await assertSucceeds(updateDoc(doc(db(BOB), 'duels', 'd1'), { guest_score: 0, guest_combo: 0 }));
  });

  test('attack: create duel pre-filled with guest/scores', async () => {
    await assertFails(addDoc(collection(db(EVE), 'duels'), { ...newDuel(EVE), host_score: 99999 }));
    await assertFails(addDoc(collection(db(EVE), 'duels'), { ...newDuel(EVE), guest_id: BOB }));
  });
  test('attack: create duel as someone else', async () => {
    await assertFails(addDoc(collection(db(EVE), 'duels'), newDuel(ALICE)));
  });
  test('attack: take over an already-joined duel as guest', async () => {
    await seedDuel('d1', { guest_id: BOB, guest_name: 'bob', status: 'in_progress' });
    await assertFails(updateDoc(doc(db(EVE), 'duels', 'd1'),
      { guest_id: EVE, guest_name: 'eve', status: 'in_progress' }));
  });
  test('attack: join and set scores in the same write', async () => {
    await seedDuel('d1');
    await assertFails(updateDoc(doc(db(EVE), 'duels', 'd1'),
      { guest_id: EVE, guest_name: 'eve', status: 'in_progress', guest_score: 99999 }));
  });
  test('attack: host joins own duel', async () => {
    await seedDuel('d1');
    await assertFails(updateDoc(doc(db(ALICE), 'duels', 'd1'),
      { guest_id: ALICE, guest_name: 'alice', status: 'in_progress' }));
  });
  test('attack: outsider writes host score', async () => {
    await seedDuel('d1');
    await assertFails(updateDoc(doc(db(EVE), 'duels', 'd1'), { host_score: 1 }));
  });
  test('attack: guest overwrites opponent score', async () => {
    await seedDuel('d1', { guest_id: BOB, status: 'in_progress', host_score: 4200 });
    await assertFails(updateDoc(doc(db(BOB), 'duels', 'd1'), { host_score: 0 }));
  });
  test('attack: resubmit a better score', async () => {
    await seedDuel('d1', { host_score: 100 });
    await assertFails(updateDoc(doc(db(ALICE), 'duels', 'd1'), { host_score: 9000 }));
  });
  test('attack: mark completed before opponent scored', async () => {
    await seedDuel('d1', { guest_id: BOB, status: 'in_progress' });
    await assertFails(updateDoc(doc(db(ALICE), 'duels', 'd1'), { host_score: 10, status: 'completed' }));
  });
  test('attack: change host / mode / code', async () => {
    await seedDuel('d1');
    await assertFails(updateDoc(doc(db(ALICE), 'duels', 'd1'), { host_id: EVE }));
    await assertFails(updateDoc(doc(db(ALICE), 'duels', 'd1'), { mode: 'classic' }));
  });
  test('attack: delete a duel', async () => {
    await seedDuel('d1');
    await assertFails(deleteDoc(doc(db(ALICE), 'duels', 'd1')));
  });
});

// ───────────────────────── friends ─────────────────────────
// Mirrors sendFriendRequest's transaction: read guard → create request → set guard.
async function sendFriendRequest(from, to) {
  const f = db(from);
  const pid = pairId(from, to);
  const stateRef = doc(f, 'friend_request_state', pid);
  const reqRef = doc(collection(f, 'friend_requests'));
  await runTransaction(f, async (tx) => {
    const s = await tx.get(stateRef);
    if (s.exists() && s.data().status === 'pending') throw new Error('pending exists');
    tx.set(reqRef, { from_uid: from, to_uid: to, from_username: 'a', from_avatar: 'default',
                     to_username: 'b', to_avatar: 'default', status: 'pending', created_at: serverTimestamp() });
    tx.set(stateRef, { user_ids: [from, to], pending_request_id: reqRef.id, status: 'pending' });
  });
  return reqRef.id;
}
// Mirrors acceptFriendRequest's transaction.
async function acceptFriendRequest(asUid, requestId, from, to) {
  const f = db(asUid);
  const pid = pairId(from, to);
  const reqRef = doc(f, 'friend_requests', requestId);
  const fsRef = doc(f, 'friendships', pid);
  const stateRef = doc(f, 'friend_request_state', pid);
  await runTransaction(f, async (tx) => {
    const r = await tx.get(reqRef);
    if (!r.exists() || r.data().status !== 'pending') throw new Error('not pending');
    tx.update(reqRef, { status: 'accepted' });
    tx.set(fsRef, { user_ids: [from, to], created_at: serverTimestamp() });
    tx.delete(stateRef);
  });
}

describe('friends', () => {
  test('client: send request (transaction incl. read of missing guard doc)', async () => {
    await assertSucceeds(sendFriendRequest(ALICE, BOB));
  });
  test('client: receiver accepts → friendship created', async () => {
    const id = await sendFriendRequest(ALICE, BOB);
    await assertSucceeds(acceptFriendRequest(BOB, id, ALICE, BOB));
    await assertSucceeds(getDoc(doc(db(ALICE), 'friendships', pairId(ALICE, BOB))));
  });
  test('client: receiver rejects, sender cancels, guard deleted', async () => {
    const id = await sendFriendRequest(ALICE, BOB);
    await assertSucceeds(updateDoc(doc(db(BOB), 'friend_requests', id), { status: 'rejected' }));
    await assertSucceeds(deleteDoc(doc(db(BOB), 'friend_request_state', pairId(ALICE, BOB))));
    const id2 = await sendFriendRequest(ALICE, BOB);
    await assertSucceeds(updateDoc(doc(db(ALICE), 'friend_requests', id2), { status: 'cancelled' }));
  });

  test('attack: befriend someone without a request', async () => {
    await assertFails(setDoc(doc(db(EVE), 'friendships', pairId(EVE, ALICE)),
      { user_ids: [EVE, ALICE], created_at: serverTimestamp() }));
  });
  test('attack: sender accepts own request', async () => {
    const id = await sendFriendRequest(EVE, ALICE);
    await assertFails(acceptFriendRequest(EVE, id, EVE, ALICE));
  });
  test('attack: friendship under a mismatched doc id', async () => {
    const id = await sendFriendRequest(ALICE, BOB);
    const f = db(BOB);
    await assertFails(runTransaction(f, async (tx) => {
      tx.update(doc(f, 'friend_requests', id), { status: 'accepted' });
      tx.set(doc(f, 'friendships', 'zzz_custom'), { user_ids: [ALICE, BOB] });
    }));
  });
  test('attack: third party pre-creates guard doc to block a pair', async () => {
    await assertFails(setDoc(doc(db(EVE), 'friend_request_state', pairId(ALICE, BOB)),
      { user_ids: [ALICE, BOB], pending_request_id: 'fake', status: 'pending' }));
  });
  test('attack: guard doc pointing at a fake request', async () => {
    await assertFails(setDoc(doc(db(ALICE), 'friend_request_state', pairId(ALICE, BOB)),
      { user_ids: [ALICE, BOB], pending_request_id: 'does_not_exist', status: 'pending' }));
  });
  test('attack: read others\' requests', async () => {
    const id = await sendFriendRequest(ALICE, BOB);
    await assertFails(getDoc(doc(db(EVE), 'friend_requests', id)));
  });
  test('attack: request with extra field changes on update', async () => {
    const id = await sendFriendRequest(ALICE, BOB);
    await assertFails(updateDoc(doc(db(BOB), 'friend_requests', id), { status: 'accepted', from_uid: EVE }));
  });
});

// ───────────────────────── duel invitations ─────────────────────────
async function sendDuelInvitation(from, to, duelId) {
  const f = db(from);
  const pid = pairId(from, to);
  const stateRef = doc(f, 'duel_invite_state', pid);
  const invRef = doc(collection(f, 'duel_invitations'));
  const expires = Timestamp.fromMillis(Date.now() + 600_000);
  await runTransaction(f, async (tx) => {
    await tx.get(stateRef);
    tx.set(invRef, { from_uid: from, to_uid: to, from_username: 'a', from_avatar: 'default',
      to_username: 'b', to_avatar: 'default', duel_id: duelId, duel_code: 'K7QX2M', mode: 'duel',
      status: 'pending', created_at: serverTimestamp(), expires_at: expires });
    tx.set(stateRef, { user_ids: [from, to], pending_invitation_id: invRef.id, status: 'pending', expires_at: expires });
  });
  return invRef.id;
}

describe('duel invitations', () => {
  test('client: host invites to own duel; invitee accepts; host marks in_progress', async () => {
    await seedDuel('d1');
    const id = await sendDuelInvitation(ALICE, BOB, 'd1');
    await assertSucceeds(updateDoc(doc(db(BOB), 'duel_invitations', id), { status: 'accepted' }));
    await assertSucceeds(deleteDoc(doc(db(BOB), 'duel_invite_state', pairId(ALICE, BOB))));
    await assertSucceeds(updateDoc(doc(db(ALICE), 'duel_invitations', id), { status: 'in_progress' }));
  });
  test('client: expired invite marked expired by a participant', async () => {
    await seed('duel_invitations/i1', { from_uid: ALICE, to_uid: BOB, duel_id: 'd1', duel_code: 'X',
      mode: 'duel', status: 'pending', expires_at: Timestamp.fromMillis(Date.now() - 1000) });
    await assertSucceeds(updateDoc(doc(db(ALICE), 'duel_invitations', 'i1'), { status: 'expired' }));
  });

  test('attack: invite pointing at someone else\'s duel', async () => {
    await seedDuel('d1'); // hosted by ALICE
    await assertFails(sendDuelInvitation(EVE, BOB, 'd1'));
  });
  test('attack: expire a still-valid invite', async () => {
    await seedDuel('d1');
    const id = await sendDuelInvitation(ALICE, BOB, 'd1');
    await assertFails(updateDoc(doc(db(BOB), 'duel_invitations', id), { status: 'expired' }));
  });
  test('attack: swap the duel an invite points to', async () => {
    await seedDuel('d1');
    const id = await sendDuelInvitation(ALICE, BOB, 'd1');
    await assertFails(updateDoc(doc(db(BOB), 'duel_invitations', id), { status: 'accepted', duel_id: 'other' }));
  });
});
