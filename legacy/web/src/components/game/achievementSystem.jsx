// Achievement system — tracks milestones
import { getCachedProfile, quickSave } from "./playerService";
import { addCoins } from "./coinSystem";

export const ACHIEVEMENTS = [
  // Game count milestones
  { id: "games_10", title: "Getting Started", desc: "Play 10 games", icon: "🎮", reward: 50, check: (s) => (s.totalGames || 0) >= 10 },
  { id: "games_50", title: "Regular Player", desc: "Play 50 games", icon: "🕹️", reward: 150, check: (s) => (s.totalGames || 0) >= 50 },
  { id: "games_100", title: "Dedicated", desc: "Play 100 games", icon: "🏅", reward: 300, check: (s) => (s.totalGames || 0) >= 100 },
  { id: "games_500", title: "Veteran", desc: "Play 500 games", icon: "🎖️", reward: 1000, check: (s) => (s.totalGames || 0) >= 500 },
  { id: "games_1000", title: "Legend", desc: "Play 1000 games", icon: "👑", reward: 2500, check: (s) => (s.totalGames || 0) >= 1000 },

  // Score milestones
  { id: "score_500", title: "Half Grand", desc: "Score 500 in one game", icon: "⭐", reward: 50, check: (s, g) => (g?.score || 0) >= 500 },
  { id: "score_1000", title: "Grand Master", desc: "Score 1000 in one game", icon: "🌟", reward: 100, check: (s, g) => (g?.score || 0) >= 1000 },
  { id: "score_2000", title: "Unstoppable", desc: "Score 2000 in one game", icon: "💫", reward: 250, check: (s, g) => (g?.score || 0) >= 2000 },
  { id: "score_5000", title: "Godlike", desc: "Score 5000 in one game", icon: "🔱", reward: 500, check: (s, g) => (g?.score || 0) >= 5000 },

  // Combo milestones
  { id: "combo_10", title: "Chain Starter", desc: "Reach 10x combo", icon: "🔗", reward: 50, check: (s, g) => (g?.maxCombo || s.highestCombo || 0) >= 10 },
  { id: "combo_20", title: "Combo Master", desc: "Reach 20x combo", icon: "⛓️", reward: 150, check: (s, g) => (g?.maxCombo || s.highestCombo || 0) >= 20 },
  { id: "combo_50", title: "Combo Legend", desc: "Reach 50x combo", icon: "💥", reward: 500, check: (s, g) => (g?.maxCombo || s.highestCombo || 0) >= 50 },

  // Duel milestones
  { id: "duel_1", title: "Duelist", desc: "Win your first duel", icon: "⚔️", reward: 50, check: (s) => (s.duelWins || 0) >= 1 },
  { id: "duel_10", title: "Duel Champion", desc: "Win 10 duels", icon: "🏆", reward: 300, check: (s) => (s.duelWins || 0) >= 10 },
  { id: "duel_50", title: "Duel King", desc: "Win 50 duels", icon: "👊", reward: 1000, check: (s) => (s.duelWins || 0) >= 50 },

  // Coin milestones
  { id: "coins_1000", title: "Coin Collector", desc: "Earn 1000 total coins", icon: "🪙", reward: 100, check: (s) => (s.totalCoinsEarned || 0) >= 1000 },
  { id: "coins_10000", title: "Rich Player", desc: "Earn 10000 total coins", icon: "💰", reward: 500, check: (s) => (s.totalCoinsEarned || 0) >= 10000 },

  // Accuracy
  { id: "perfect_100", title: "Sharpshooter", desc: "Hit 100 perfect taps", icon: "🎯", reward: 100, check: (s) => (s.perfectTaps || 0) >= 100 },
  { id: "perfect_1000", title: "Eagle Eye", desc: "Hit 1000 perfect taps", icon: "🦅", reward: 500, check: (s) => (s.perfectTaps || 0) >= 1000 },

  // Streak
  { id: "streak_7", title: "Weekly Warrior", desc: "7-day login streak", icon: "🔥", reward: 200, check: (s, g, p) => (p?.daily_rewards?.streak || 0) >= 7 },
];

// Check and unlock new achievements — returns array of newly unlocked
export function checkAchievements(gameData) {
  const p = getCachedProfile();
  const stats = p?.stats || {};
  const unlocked = p?.achievements || [];
  const newlyUnlocked = [];

  for (const ach of ACHIEVEMENTS) {
    if (unlocked.includes(ach.id)) continue;
    if (ach.check(stats, gameData, p)) {
      newlyUnlocked.push(ach);
    }
  }

  if (newlyUnlocked.length > 0) {
    const newUnlockedIds = [...unlocked, ...newlyUnlocked.map(a => a.id)];
    let totalReward = 0;
    for (const a of newlyUnlocked) totalReward += a.reward;
    if (totalReward > 0) addCoins(totalReward);
    quickSave({ achievements: newUnlockedIds });
  }

  return newlyUnlocked;
}

export function getUnlockedAchievements() {
  const p = getCachedProfile();
  return p?.achievements || [];
}

export function getAchievementProgress() {
  const unlocked = getUnlockedAchievements();
  return { unlocked: unlocked.length, total: ACHIEVEMENTS.length };
}