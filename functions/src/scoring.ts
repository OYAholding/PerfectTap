// Pure score-plausibility rules — no Firebase imports, unit-tested in test/scoring.test.ts.
//
// Mirrors PerfectTap/Utils/GameConfig.swift + Models/GameMode.swift. If those
// change (points, multipliers, timers), update MODES below and the tests.
//
// What this can prove: a submitted score is achievable in the REAL (server-
// measured) time the session lasted, with the reported tap count. What it
// cannot prove: that the taps were actually that accurate. That needs server
// replay of a tap log (roadmap).

export const PERFECT_POINTS = 100;

/** Fastest sustained tap rate we consider human (taps/second), incl. two thumbs. */
export const MAX_TAPS_PER_SECOND = 12;

/** Grace for network latency / clock skew between start and submit. */
export const ELAPSED_SLACK_SECONDS = 5;

export interface ModeRules {
  /** Ranked on the global leaderboard. */
  ranked: boolean;
  /** Highest combo multiplier reachable in this mode. */
  maxComboMultiplier: number;
  /** Fixed run length for timer modes (seconds); undefined = open-ended. */
  timerSeconds?: number;
  /** Extra score multiplier the client may apply (Classic score boost). */
  boostMultiplier?: number;
}

// Keys are GameMode.rawValue from Swift.
export const MODES: Record<string, ModeRules> = {
  classic:        { ranked: true, maxComboMultiplier: 2, boostMultiplier: 2 },
  endless:        { ranked: true, maxComboMultiplier: 2 },
  timed:          { ranked: true, maxComboMultiplier: 2, timerSeconds: 60 },
  sudden_death:   { ranked: true, maxComboMultiplier: 2 },
  combo_frenzy:   { ranked: true, maxComboMultiplier: 6 },
  precision:      { ranked: true, maxComboMultiplier: 2 },
  chaos:          { ranked: true, maxComboMultiplier: 2 },
  mirror:         { ranked: true, maxComboMultiplier: 2 },
  invisible_zone: { ranked: true, maxComboMultiplier: 2 },
  rush:           { ranked: true, maxComboMultiplier: 2, timerSeconds: 30 },
  hardcore_combo: { ranked: true, maxComboMultiplier: 2 },
  tiny_window:    { ranked: true, maxComboMultiplier: 2 },
  // Not ranked: no score (zen, focus) or scored in the duel doc instead.
  zen:            { ranked: false, maxComboMultiplier: 1 },
  focus:          { ranked: false, maxComboMultiplier: 1 },
  duel:           { ranked: false, maxComboMultiplier: 2 },
};

export interface Submission {
  mode: string;
  score: number;
  maxCombo: number;
  taps: number;
  perfects: number;
}

export type Verdict =
  | { ok: true }
  | { ok: false; reason: string };

const isNonNegInt = (v: unknown): v is number =>
  typeof v === 'number' && Number.isInteger(v) && v >= 0;

/** Parses untrusted callable input into a Submission, or returns why not. */
export function parseSubmission(raw: unknown): Submission | { error: string } {
  if (typeof raw !== 'object' || raw === null) return { error: 'invalid_payload' };
  const r = raw as Record<string, unknown>;
  if (typeof r.mode !== 'string' || !(r.mode in MODES)) return { error: 'unknown_mode' };
  for (const k of ['score', 'maxCombo', 'taps', 'perfects'] as const) {
    if (!isNonNegInt(r[k])) return { error: `invalid_${k}` };
  }
  return {
    mode: r.mode,
    score: r.score as number,
    maxCombo: r.maxCombo as number,
    taps: r.taps as number,
    perfects: r.perfects as number,
  };
}

/**
 * Is `s` achievable in `elapsedSeconds` of real (server-measured) time?
 * Every check is an upper bound a genuine run can never exceed.
 */
export function checkPlausibility(s: Submission, elapsedSeconds: number): Verdict {
  const rules = MODES[s.mode];
  if (!rules) return { ok: false, reason: 'unknown_mode' };
  if (!rules.ranked) return { ok: false, reason: 'mode_not_ranked' };

  if (s.perfects > s.taps) return { ok: false, reason: 'perfects_exceed_taps' };
  if (s.maxCombo > s.taps) return { ok: false, reason: 'combo_exceeds_taps' };

  // Timer modes can't be played longer than their clock (+ revive bonus slack).
  // Elapsed time is capped for the tap-rate bound below.
  const cap = rules.timerSeconds !== undefined ? rules.timerSeconds + 15 : Infinity; // +15s revive bonus
  const playable = Math.min(elapsedSeconds, cap) + ELAPSED_SLACK_SECONDS;

  // 3-second countdown happens inside the session before taps are accepted.
  const tappable = Math.max(0, playable - 3);
  const maxTaps = Math.floor(tappable * MAX_TAPS_PER_SECOND);
  if (s.taps > maxTaps) return { ok: false, reason: 'too_many_taps_for_time' };

  const maxPerTap = PERFECT_POINTS * rules.maxComboMultiplier * (rules.boostMultiplier ?? 1);
  if (s.score > s.taps * maxPerTap) return { ok: false, reason: 'score_exceeds_taps' };

  return { ok: true };
}
