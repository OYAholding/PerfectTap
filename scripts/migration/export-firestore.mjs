#!/usr/bin/env node
// Read-only export of the Firestore data PerfectTap migrates to Supabase.
// Writes one CSV ready for:  \copy legacy.raw_docs (collection, doc_id, parent_id, data) from 'firestore-export.csv' csv
//
// Usage (needs read access to perfecttap-48a08; never commit the output — it holds player data):
//   cd scripts/migration && npm ci
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node export-firestore.mjs ./firestore-export.csv
//   (or `gcloud auth application-default login` instead of the key file)
//
// Migrated: players, friendships, leaderboard/{mode}/scores.
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

async function dumpCollection(name) {
  let last = null;
  for (;;) {
    let q = db.collection(name).orderBy('__name__').limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) emit(name, doc.id, '', doc.data());
    last = snap.docs[snap.docs.length - 1];
  }
}

await dumpCollection('players');
await dumpCollection('friendships');
const scores = await db.collectionGroup('scores').get();
for (const doc of scores.docs) {
  const mode = doc.ref.parent.parent?.id;
  if (doc.ref.parent.parent?.parent?.id === 'leaderboard' && mode) emit('leaderboard', doc.id, mode, doc.data());
}
await new Promise((r) => stream.end(r));
console.log(JSON.stringify({ project: PROJECT_ID, out, counts }));
