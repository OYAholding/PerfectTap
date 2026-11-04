// End-to-end tests against the Auth + Firestore + Functions emulators.
// Run: npm run test:emulator
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp, type FirebaseApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, signInAnonymously, signOut } from 'firebase/auth';
import { getFunctions, connectFunctionsEmulator, httpsCallable } from 'firebase/functions';
import {
  getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc,
} from 'firebase/firestore';

let app: FirebaseApp;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

before(async () => {
  app = initializeApp({ projectId: 'demo-perfecttap', apiKey: 'demo-key' });
  connectAuthEmulator(getAuth(app), 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFunctionsEmulator(getFunctions(app, 'europe-west1'), '127.0.0.1', 5001);
  connectFirestoreEmulator(getFirestore(app), '127.0.0.1', 8080);
});
after(async () => { await deleteApp(app); });

const fns = () => getFunctions(app, 'europe-west1');
const call = async <T = any>(name: string, data: unknown): Promise<T> =>
  (await httpsCallable(fns(), name)(data)).data as T;

async function newPlayer(username: string): Promise<string> {
  const auth = getAuth(app);
  await signOut(auth).catch(() => {});
  const { user } = await signInAnonymously(auth);
  // Same shape the iOS client writes (allowed by firestore.rules).
  await setDoc(doc(getFirestore(app), 'players', user.uid),
    { uid: user.uid, username, username_lower: username.toLowerCase(), coins: 0, level: 1 }, { merge: true });
  return user.uid;
}

const errCode = async (p: Promise<unknown>) => {
  try { await p; return 'ok'; } catch (e: any) { return e.code as string; }
};

test('unauthenticated calls are refused', async () => {
  await signOut(getAuth(app));
  assert.equal(await errCode(call('startGame', { mode: 'classic' })), 'functions/unauthenticated');
  assert.equal(await errCode(call('submitScore', { mode: 'classic', score: 1 })), 'functions/unauthenticated');
});

test('legacy client payload (no session) gets update_required, not an error', async () => {
  await newPlayer('legacy_user');
  const r = await call('submitScore', { mode: 'classic', score: 170, maxCombo: 1 });
  assert.deepEqual(r, { accepted: false, reason: 'update_required' });
});

test('full flow: start → play → submit → verified leaderboard entry', async () => {
  const uid = await newPlayer('qa_flow');
  const { sessionId } = await call<{ sessionId: string }>('startGame', { mode: 'classic' });
  assert.ok(sessionId);
  await sleep(1500);
  const r = await call('submitScore', { sessionId, mode: 'classic', score: 170, maxCombo: 1, taps: 5, perfects: 1 });
  assert.deepEqual(r, { accepted: true, ranked: true, newBest: true, verifiedScore: 170 });

  const entry = await getDoc(doc(getFirestore(app), 'leaderboard', 'classic', 'scores', uid));
  assert.equal(entry.data()?.score, 170);
  assert.equal(entry.data()?.username, 'qa_flow');
});

test('session is single-use', async () => {
  await newPlayer('qa_reuse');
  const { sessionId } = await call<{ sessionId: string }>('startGame', { mode: 'classic' });
  const payload = { sessionId, mode: 'classic', score: 40, maxCombo: 0, taps: 1, perfects: 0 };
  assert.equal((await call('submitScore', payload)).accepted, true);
  assert.deepEqual(await call('submitScore', payload), { accepted: false, reason: 'session_used' });
});

test('lower score keeps the existing best', async () => {
  await newPlayer('qa_keep');
  let { sessionId } = await call<{ sessionId: string }>('startGame', { mode: 'endless' });
  await call('submitScore', { sessionId, mode: 'endless', score: 300, maxCombo: 2, taps: 3, perfects: 3 });
  ({ sessionId } = await call<{ sessionId: string }>('startGame', { mode: 'endless' }));
  const r = await call('submitScore', { sessionId, mode: 'endless', score: 100, maxCombo: 1, taps: 1, perfects: 1 });
  assert.deepEqual(r, { accepted: true, ranked: true, newBest: false, verifiedScore: 100 });
});

test('attack: instant giant score is rejected and burns the session', async () => {
  await newPlayer('qa_cheat');
  const { sessionId } = await call<{ sessionId: string }>('startGame', { mode: 'classic' });
  const r = await call('submitScore', { sessionId, mode: 'classic', score: 999999, maxCombo: 999, taps: 2500, perfects: 2500 });
  assert.equal(r.accepted, false);
  assert.equal(r.reason, 'too_many_taps_for_time');
  const again = await call('submitScore', { sessionId, mode: 'classic', score: 10, maxCombo: 0, taps: 1, perfects: 0 });
  assert.deepEqual(again, { accepted: false, reason: 'session_used' });
});

test('attack: someone else\'s session / mode swap / fake session', async () => {
  await newPlayer('qa_owner');
  const { sessionId } = await call<{ sessionId: string }>('startGame', { mode: 'classic' });
  await newPlayer('qa_thief');
  const body = { sessionId, mode: 'classic', score: 40, maxCombo: 0, taps: 1, perfects: 0 };
  assert.deepEqual(await call('submitScore', body), { accepted: false, reason: 'invalid_session' });
  const own = (await call<{ sessionId: string }>('startGame', { mode: 'rush' })).sessionId;
  assert.deepEqual(await call('submitScore', { ...body, sessionId: own }), { accepted: false, reason: 'mode_mismatch' });
  assert.deepEqual(await call('submitScore', { ...body, sessionId: 'made_up' }), { accepted: false, reason: 'invalid_session' });
});

test('attack: malformed numbers are rejected', async () => {
  await newPlayer('qa_bad');
  const { sessionId } = await call<{ sessionId: string }>('startGame', { mode: 'classic' });
  assert.equal(await errCode(call('submitScore', { sessionId, mode: 'classic', score: -5, maxCombo: 0, taps: 0, perfects: 0 })),
    'functions/invalid-argument');
  assert.equal(await errCode(call('startGame', { mode: 'not_a_mode' })), 'functions/invalid-argument');
});

test('attack: clients cannot write the verified leaderboard directly', async () => {
  const uid = await newPlayer('qa_direct');
  assert.equal(await errCode(setDoc(doc(getFirestore(app), 'leaderboard', 'classic', 'scores', uid), { score: 1e6 })),
    'permission-denied');
});

test('attack: session spam is rate limited', async () => {
  await newPlayer('qa_spam');
  const codes: string[] = [];
  for (let i = 0; i < 22; i++) codes.push(await errCode(call('startGame', { mode: 'classic' })));
  assert.equal(codes.filter((c) => c === 'ok').length, 20);
  assert.ok(codes.includes('functions/resource-exhausted'));
});
