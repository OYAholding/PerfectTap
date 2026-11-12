// PerfectTap Cloud Functions (2nd gen).
//
//   startGame   → issues a server-timed, single-use game session.
//   submitScore → validates a finished run against its session and, if
//                 plausible, updates the VERIFIED leaderboard
//                 leaderboard/{mode}/scores/{uid}. Only this code writes there
//                 (firestore.rules: `allow write: if false`).
//
// The client's own players/{uid}.best_* stay as private progress; the global
// leaderboard reads the verified collection.

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { setGlobalOptions, logger } from 'firebase-functions/v2';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { MODES, parseSubmission, checkPlausibility } from './scoring.js';

initializeApp();
const db = getFirestore();

// Firestore lives in eur3; keep functions in Europe. maxInstances caps cost
// if someone hammers the endpoints.
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });

export const SESSION_TTL_MS = 2 * 60 * 60 * 1000;   // a run can't last longer than 2h
export const RATE_WINDOW_MS = 60 * 1000;
export const RATE_MAX_SESSIONS = 20;                // per user per minute

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  return auth.uid;
}

// ─── startGame ──────────────────────────────────────────────────────────
export const startGame = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const mode = (req.data as { mode?: unknown } | undefined)?.mode;
  if (typeof mode !== 'string' || !(mode in MODES)) {
    throw new HttpsError('invalid-argument', 'unknown_mode');
  }

  const rateRef = db.doc(`game_rate/${uid}`);
  const sessionRef = db.collection('game_sessions').doc();

  await db.runTransaction(async (tx) => {
    const now = Date.now();
    const rate = (await tx.get(rateRef)).data() as { window_start?: number; count?: number } | undefined;
    const inWindow = rate?.window_start !== undefined && now - rate.window_start < RATE_WINDOW_MS;
    const count = inWindow ? (rate?.count ?? 0) : 0;
    if (count >= RATE_MAX_SESSIONS) {
      throw new HttpsError('resource-exhausted', 'rate_limited');
    }
    tx.set(rateRef, { window_start: inWindow ? rate!.window_start : now, count: count + 1 });
    tx.set(sessionRef, {
      uid,
      mode,
      started_at: FieldValue.serverTimestamp(),
      expires_at: Timestamp.fromMillis(now + SESSION_TTL_MS),  // Firestore TTL field
      used: false,
    });
  });

  return { sessionId: sessionRef.id };
});

// ─── submitScore ────────────────────────────────────────────────────────
type SubmitResult =
  | { accepted: true; ranked: true; newBest: boolean; verifiedScore: number }
  | { accepted: false; reason: string };

export const submitScore = onCall(async (req): Promise<SubmitResult> => {
  const uid = requireUid(req.auth);
  const data = (req.data ?? {}) as Record<string, unknown>;

  // App builds ≤ 1.0.2 call without a session. They ignore the response, so
  // answer politely instead of erroring; their score just isn't ranked.
  if (typeof data.sessionId !== 'string' || data.sessionId.length === 0) {
    return { accepted: false, reason: 'update_required' };
  }

  const parsed = parseSubmission(data);
  if ('error' in parsed) throw new HttpsError('invalid-argument', parsed.error);

  const sessionRef = db.doc(`game_sessions/${data.sessionId}`);
  const entryRef = db.doc(`leaderboard/${parsed.mode}/scores/${uid}`);
  const playerRef = db.doc(`players/${uid}`);

  const result = await db.runTransaction(async (tx): Promise<SubmitResult> => {
    // All reads first (Firestore transactions forbid reads after writes).
    const [sessionSnap, entrySnap, playerSnap] = await Promise.all([
      tx.get(sessionRef), tx.get(entryRef), tx.get(playerRef),
    ]);
    const session = sessionSnap.data() as
      | { uid: string; mode: string; started_at?: Timestamp; expires_at: Timestamp; used: boolean }
      | undefined;

    if (!session || session.uid !== uid) return { accepted: false, reason: 'invalid_session' };
    if (session.mode !== parsed.mode) return { accepted: false, reason: 'mode_mismatch' };
    if (session.used) return { accepted: false, reason: 'session_used' };
    if (!session.started_at || session.expires_at.toMillis() < Date.now()) {
      return { accepted: false, reason: 'session_expired' };
    }

    // Burn the session whatever the verdict — one submission per run.
    tx.update(sessionRef, { used: true, submitted_at: FieldValue.serverTimestamp() });

    const elapsedSeconds = (Date.now() - session.started_at.toMillis()) / 1000;
    const verdict = checkPlausibility(parsed, elapsedSeconds);
    if (!verdict.ok) return { accepted: false, reason: verdict.reason };

    const previous = (entrySnap.data()?.score as number | undefined) ?? -1;
    const newBest = parsed.score > previous;
    if (newBest) {
      tx.set(entryRef, {
        uid,
        username: (playerSnap.data()?.username as string | undefined) ?? '',
        score: parsed.score,
        max_combo: parsed.maxCombo,
        session_id: sessionRef.id,
        updated_at: FieldValue.serverTimestamp(),
      });
    }
    return { accepted: true, ranked: true, newBest, verifiedScore: parsed.score };
  });

  if (!result.accepted && result.reason !== 'update_required') {
    // Monitoring signal for cheating attempts / client bugs.
    logger.warn('submitScore rejected', { uid, mode: parsed.mode, score: parsed.score, reason: result.reason });
  }
  return result;
});
