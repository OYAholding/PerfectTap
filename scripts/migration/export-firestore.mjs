#!/usr/bin/env node
// Read-only export of the Firestore data PerfectTap migrates to Supabase.
// Writes one CSV ready for:  \copy legacy.raw_docs (collection, doc_id, parent_id, data) from 'firestore-export.csv' csv
//
// Usage (needs read access to perfecttap-48a08; never commit the output — it holds player data):
//   cd scripts/migration && npm ci
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node export-firestore.mjs ./firestore-export.csv
//   (or `gcloud auth application-default login` instead of the key file)
//
// Migrated: players, friendships (+ mutual players.friends mirrors), leaderboard/{mode}/scores.
// Not migrated (short-lived): duels, duel_invitations, friend_requests, *_state guards, game_sessions.
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { createWriteStream } from 'node:fs';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'perfecttap-48a08';
const out = process.argv[2] ?? 'firestore-export.csv';

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
const db = getFirestore();

/** Firestore values → plain JSON (Timestamps → ISO strings). */
function plain(v) {
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === 'object') {
    if (typeof v.toDate === 'function') return v.toDate().toISOString();
    if (typeof v.latitude === 'number' && typeof v.longitude === 'number') return { lat: v.latitude, lng: v.longitude };
    if (typeof v.path === 'string' && typeof v.id === 'string') return v.path; // DocumentReference
    return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, plain(x)]));
  }
  return v;
}

const csv = (s) => `"${String(s).replaceAll('"', '""')}"`;
const stream = createWriteStream(out, { mode: 0o600 });
const counts = {};
function emit(collection, docId, parentId, data) {
  stream.write([csv(collection), csv(docId), csv(parentId), csv(JSON.stringify(plain(data)))].join(',') + '\n');
  counts[collection] = (counts[collection] ?? 0) + 1;
}

const friendsOf = new Map(); // players.friends arrays (pre-canonical app versions)
const canonicalPairs = new Set();
const pairKey = (a, b) => (a < b ? `${a}_${b}` : `${b}_${a}`);

async function dumpCollection(name) {
  let last = null;
  for (;;) {
    let q = db.collection(name).orderBy('__name__').limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const data = doc.data();
      emit(name, doc.id, '', data);
      if (name === 'players' && Array.isArray(data.friends)) friendsOf.set(doc.id, new Set(data.friends));
      if (name === 'friendships' && Array.isArray(data.user_ids) && data.user_ids.length === 2) {
        canonicalPairs.add(pairKey(data.user_ids[0], data.user_ids[1]));
      }
    }
    last = snap.docs[snap.docs.length - 1];
  }
}

await dumpCollection('players');
await dumpCollection('friendships');
// Older app versions only wrote the players.friends mirror. Carry a pair over only when
// BOTH players list each other (a one-sided entry is not proof of an accepted request).
for (const [a, fa] of friendsOf) for (const b of fa) {
  if (a < b && friendsOf.get(b)?.has(a) && !canonicalPairs.has(pairKey(a, b))) {
    emit('friendships', `mirror:${pairKey(a, b)}`, '', { user_ids: [a, b], created_at: null });
  }
}
const scores = await db.collectionGroup('scores').get();
for (const doc of scores.docs) {
  const mode = doc.ref.parent.parent?.id;
  if (doc.ref.parent.parent?.parent?.id === 'leaderboard' && mode) emit('leaderboard', doc.id, mode, doc.data());
}
await new Promise((r) => stream.end(r));
console.log(JSON.stringify({ project: PROJECT_ID, out, counts }));
