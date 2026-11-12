import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkPlausibility, parseSubmission, type Submission } from '../src/scoring.js';

const run = (o: Partial<Submission>): Submission =>
  ({ mode: 'classic', score: 0, maxCombo: 0, taps: 0, perfects: 0, ...o });

test('real game from the simulator play-test is accepted', () => {
  // 170 pts, 5 taps, 1 perfect, ~10s session.
  assert.deepEqual(checkPlausibility(run({ score: 170, taps: 5, perfects: 1, maxCombo: 1 }), 10), { ok: true });
});

test('strong but legit classic run: 300 taps in 90s, ×2 combo', () => {
  assert.deepEqual(checkPlausibility(run({ score: 300 * 200, taps: 300, perfects: 250, maxCombo: 120 }), 90), { ok: true });
});

test('combo frenzy can legitimately reach ×6', () => {
  assert.deepEqual(checkPlausibility(run({ mode: 'combo_frenzy', score: 100 * 600, taps: 100, perfects: 100, maxCombo: 100 }), 60), { ok: true });
});

test('instant huge score is rejected (no time to play)', () => {
  assert.equal(checkPlausibility(run({ score: 50000, taps: 400, perfects: 400, maxCombo: 400 }), 2).ok, false);
});

test('score above what the taps can produce is rejected', () => {
  const v = checkPlausibility(run({ score: 10000, taps: 10, perfects: 10, maxCombo: 10 }), 60);
  assert.deepEqual(v, { ok: false, reason: 'score_exceeds_taps' });
});

test('more perfects / combo than taps is rejected', () => {
  assert.deepEqual(checkPlausibility(run({ taps: 5, perfects: 6 }), 60), { ok: false, reason: 'perfects_exceed_taps' });
  assert.deepEqual(checkPlausibility(run({ taps: 5, maxCombo: 6 }), 60), { ok: false, reason: 'combo_exceeds_taps' });
});

test('timed mode cannot be stretched past its clock', () => {
  // 60s timer: even if the session stays open 10 minutes, taps are bounded by ~80s.
  const v = checkPlausibility(run({ mode: 'timed', taps: 2000, score: 1000, perfects: 0 }), 600);
  assert.deepEqual(v, { ok: false, reason: 'too_many_taps_for_time' });
});

test('unranked modes are not ranked', () => {
  for (const mode of ['zen', 'focus', 'duel']) {
    assert.deepEqual(checkPlausibility(run({ mode }), 60), { ok: false, reason: 'mode_not_ranked' });
  }
});

test('parseSubmission rejects bad input', () => {
  assert.deepEqual(parseSubmission(null), { error: 'invalid_payload' });
  assert.deepEqual(parseSubmission({ mode: 'nope' }), { error: 'unknown_mode' });
  assert.deepEqual(parseSubmission({ mode: 'classic', score: -1, maxCombo: 0, taps: 0, perfects: 0 }), { error: 'invalid_score' });
  assert.deepEqual(parseSubmission({ mode: 'classic', score: 1.5, maxCombo: 0, taps: 0, perfects: 0 }), { error: 'invalid_score' });
  assert.deepEqual(parseSubmission({ mode: 'classic', score: '9', maxCombo: 0, taps: 0, perfects: 0 }), { error: 'invalid_score' });
  assert.deepEqual(parseSubmission({ mode: 'classic', score: 1, maxCombo: 0, taps: 1 }), { error: 'invalid_perfects' });
});
