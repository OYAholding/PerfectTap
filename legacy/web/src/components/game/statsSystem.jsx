// Player statistics tracking system — reads/writes through playerService cache

import { getCachedProfile, quickSave } from "./playerService";

function getDefaultStats() {
  return {
    totalGames: 0,
    totalScore: 0,
    highestCombo: 0,
    totalDuels: 0,
    duelWins: 0,
    duelLosses: 0,
    duelTies: 0,
    favoriteMode: "classic",
    modeCounts: {},
    totalCoinsEarned: 0,
    questsCompleted: 0,
    perfectTaps: 0,
    totalTaps: 0,
  };
}

export function getStats() {
  const p = getCachedProfile();
  if (!p?.stats) return getDefaultStats();
  return { ...getDefaultStats(), ...p.stats };
}

function saveStats(stats) {
  quickSave({ stats });
}

export function recordGame({ mode, score, maxCombo, coinsEarned, perfectCount, tapCount }) {
  const stats = getStats();
  stats.totalGames += 1;
  stats.totalScore += score;
  stats.highestCombo = Math.max(stats.highestCombo, maxCombo);
  stats.totalCoinsEarned += coinsEarned || 0;
  stats.perfectTaps += perfectCount || 0;
  stats.totalTaps += tapCount || 0;

  stats.modeCounts[mode] = (stats.modeCounts[mode] || 0) + 1;
  
  let maxCount = 0;
  let fav = "classic";
  for (const [m, c] of Object.entries(stats.modeCounts)) {
    if (c > maxCount) { maxCount = c; fav = m; }
  }
  stats.favoriteMode = fav;

  saveStats(stats);

  // Also save to recent_matches
  addRecentMatch({ mode, score, maxCombo, date: new Date().toISOString() });

  return stats;
}

export function addRecentMatch(match) {
  const p = getCachedProfile();
  const recent = [...(p?.recent_matches || [])];
  recent.unshift(match);
  quickSave({ recent_matches: recent.slice(0, 20) });
}

export function recordDuel(result, opponentName, myScore, opponentScore) {
  const stats = getStats();
  stats.totalDuels += 1;
  if (result === "win") stats.duelWins += 1;
  else if (result === "loss") stats.duelLosses += 1;
  else stats.duelTies += 1;
  saveStats(stats);

  addRecentMatch({
    mode: "duel",
    score: myScore || 0,
    result,
    opponent: opponentName || "Unknown",
    date: new Date().toISOString(),
  });

  return stats;
}

export function incrementQuestsCompleted() {
  const stats = getStats();
  stats.questsCompleted += 1;
  saveStats(stats);
}