// Season Pass system — tracks seasonal progress with free & premium reward tiers
import { getCachedProfile, quickSave } from "./playerService";
import { addCoins } from "./coinSystem";
import { addOwnedItem } from "./coinSystem";

// Current season config
export const CURRENT_SEASON = {
  id: "s1",
  name: "Season 1: Neon Nights",
  icon: "🌃",
  startDate: "2026-03-01",
  endDate: "2026-05-31",
  maxTier: 30,
  xpPerTier: 200, // season XP needed per tier
};

// Reward tiers — free track is available to everyone
// premium track requires "season pass" purchase (coins)
export const SEASON_REWARDS = [
  { tier: 1, free: { type: "coins", amount: 50, label: "50 Coins", icon: "🪙" }, premium: { type: "coins", amount: 100, label: "100 Coins", icon: "💰" } },
  { tier: 2, free: { type: "coins", amount: 75, label: "75 Coins", icon: "🪙" }, premium: null },
  { tier: 3, free: null, premium: { type: "avatar", id: "av_neon_cat", label: "Neon Cat 🐱", icon: "🐱" } },
  { tier: 4, free: { type: "coins", amount: 100, label: "100 Coins", icon: "🪙" }, premium: { type: "coins", amount: 150, label: "150 Coins", icon: "💰" } },
  { tier: 5, free: { type: "badge", id: "badge_s1_5", label: "Tier 5 Badge", icon: "⭐" }, premium: { type: "theme", id: "neon", label: "Neon Theme", icon: "✨" } },
  { tier: 6, free: { type: "coins", amount: 100, label: "100 Coins", icon: "🪙" }, premium: null },
  { tier: 7, free: null, premium: { type: "coins", amount: 200, label: "200 Coins", icon: "💰" } },
  { tier: 8, free: { type: "coins", amount: 125, label: "125 Coins", icon: "🪙" }, premium: { type: "avatar", id: "av_robot", label: "Robot 🤖", icon: "🤖" } },
  { tier: 9, free: { type: "coins", amount: 150, label: "150 Coins", icon: "🪙" }, premium: null },
  { tier: 10, free: { type: "badge", id: "badge_s1_10", label: "Tier 10 Badge", icon: "🌟" }, premium: { type: "theme", id: "fire", label: "Fire Theme", icon: "🔥" } },
  { tier: 11, free: { type: "coins", amount: 150, label: "150 Coins", icon: "🪙" }, premium: { type: "coins", amount: 250, label: "250 Coins", icon: "💰" } },
  { tier: 12, free: null, premium: { type: "avatar", id: "av_ghost", label: "Ghost 👻", icon: "👻" } },
  { tier: 13, free: { type: "coins", amount: 175, label: "175 Coins", icon: "🪙" }, premium: null },
  { tier: 14, free: { type: "coins", amount: 200, label: "200 Coins", icon: "🪙" }, premium: { type: "coins", amount: 300, label: "300 Coins", icon: "💰" } },
  { tier: 15, free: { type: "badge", id: "badge_s1_15", label: "Tier 15 Badge", icon: "💫" }, premium: { type: "theme", id: "ice", label: "Arctic Theme", icon: "❄️" } },
  { tier: 16, free: { type: "coins", amount: 200, label: "200 Coins", icon: "🪙" }, premium: null },
  { tier: 17, free: null, premium: { type: "coins", amount: 350, label: "350 Coins", icon: "💰" } },
  { tier: 18, free: { type: "coins", amount: 225, label: "225 Coins", icon: "🪙" }, premium: { type: "avatar", id: "av_dragon", label: "Dragon 🐉", icon: "🐉" } },
  { tier: 19, free: { type: "coins", amount: 250, label: "250 Coins", icon: "🪙" }, premium: null },
  { tier: 20, free: { type: "badge", id: "badge_s1_20", label: "Tier 20 Badge", icon: "🏅" }, premium: { type: "theme", id: "galaxy", label: "Galaxy Theme", icon: "🌌" } },
  { tier: 21, free: { type: "coins", amount: 250, label: "250 Coins", icon: "🪙" }, premium: { type: "coins", amount: 400, label: "400 Coins", icon: "💰" } },
  { tier: 22, free: null, premium: { type: "avatar", id: "av_alien", label: "Alien 👽", icon: "👽" } },
  { tier: 23, free: { type: "coins", amount: 275, label: "275 Coins", icon: "🪙" }, premium: null },
  { tier: 24, free: { type: "coins", amount: 300, label: "300 Coins", icon: "🪙" }, premium: { type: "coins", amount: 500, label: "500 Coins", icon: "💰" } },
  { tier: 25, free: { type: "badge", id: "badge_s1_25", label: "Tier 25 Badge", icon: "👑" }, premium: { type: "theme", id: "gold", label: "Gold Theme", icon: "🏆" } },
  { tier: 26, free: { type: "coins", amount: 300, label: "300 Coins", icon: "🪙" }, premium: null },
  { tier: 27, free: null, premium: { type: "coins", amount: 600, label: "600 Coins", icon: "💰" } },
  { tier: 28, free: { type: "coins", amount: 350, label: "350 Coins", icon: "🪙" }, premium: { type: "avatar", id: "av_crown", label: "Crown 👑", icon: "👑" } },
  { tier: 29, free: { type: "coins", amount: 400, label: "400 Coins", icon: "🪙" }, premium: null },
  { tier: 30, free: { type: "badge", id: "badge_s1_max", label: "Season 1 Master", icon: "🏆" }, premium: { type: "coins", amount: 1000, label: "1000 Coins + Exclusive", icon: "💎" } },
];

// Get season pass state from profile
export function getSeasonData() {
  const p = getCachedProfile();
  const data = p?.season_pass || {};
  return {
    seasonId: data.seasonId || null,
    seasonXP: data.seasonXP || 0,
    tier: data.tier || 0,
    isPremium: data.isPremium || false,
    claimedFree: data.claimedFree || [],
    claimedPremium: data.claimedPremium || [],
  };
}

// Initialize season if not started or if new season
export function initSeason() {
  const data = getSeasonData();
  if (data.seasonId === CURRENT_SEASON.id) return data;

  // New season — reset progress
  const newData = {
    seasonId: CURRENT_SEASON.id,
    seasonXP: 0,
    tier: 0,
    isPremium: false,
    claimedFree: [],
    claimedPremium: [],
  };
  quickSave({ season_pass: newData });
  return newData;
}

// Award season XP (called after each game)
export function awardSeasonXP(amount) {
  const data = getSeasonData();
  if (data.seasonId !== CURRENT_SEASON.id) return data;

  let xp = data.seasonXP + amount;
  let tier = data.tier;

  // Level up tiers
  while (xp >= CURRENT_SEASON.xpPerTier && tier < CURRENT_SEASON.maxTier) {
    xp -= CURRENT_SEASON.xpPerTier;
    tier += 1;
  }
  // Cap XP at max tier
  if (tier >= CURRENT_SEASON.maxTier) {
    tier = CURRENT_SEASON.maxTier;
    xp = 0;
  }

  const updated = { ...data, seasonXP: xp, tier };
  quickSave({ season_pass: updated });
  return updated;
}

// Claim a free tier reward
export function claimFreeReward(tierNum) {
  const data = getSeasonData();
  if (data.tier < tierNum) return false;
  if (data.claimedFree.includes(tierNum)) return false;

  const reward = SEASON_REWARDS.find(r => r.tier === tierNum)?.free;
  if (!reward) return false;

  applyReward(reward);
  const updated = { ...data, claimedFree: [...data.claimedFree, tierNum] };
  quickSave({ season_pass: updated });
  return reward;
}

// Claim a premium tier reward
export function claimPremiumReward(tierNum) {
  const data = getSeasonData();
  if (!data.isPremium) return false;
  if (data.tier < tierNum) return false;
  if (data.claimedPremium.includes(tierNum)) return false;

  const reward = SEASON_REWARDS.find(r => r.tier === tierNum)?.premium;
  if (!reward) return false;

  applyReward(reward);
  const updated = { ...data, claimedPremium: [...data.claimedPremium, tierNum] };
  quickSave({ season_pass: updated });
  return reward;
}

// Purchase premium pass
export function purchasePremiumPass() {
  const data = getSeasonData();
  if (data.isPremium) return false;

  const updated = { ...data, isPremium: true };
  quickSave({ season_pass: updated });
  return true;
}

function applyReward(reward) {
  if (reward.type === "coins") {
    addCoins(reward.amount);
  } else if (reward.type === "theme" || reward.type === "avatar" || reward.type === "badge") {
    addOwnedItem(reward.id);
  }
}

// Calculate season XP from a game (similar to regular XP but separate track)
export function calcSeasonXP(score, maxCombo, mode) {
  let base = Math.floor(score / 25);
  const comboBonus = Math.floor(maxCombo / 3);
  const modeBonus = mode === "duel" ? 15 : mode === "sudden_death" ? 10 : 5;
  return Math.max(3, base + comboBonus + modeBonus);
}

// Days remaining in season
export function getSeasonDaysLeft() {
  const end = new Date(CURRENT_SEASON.endDate);
  const now = new Date();
  const diff = Math.ceil((end - now) / (1000 * 60 * 60 * 24));
  return Math.max(0, diff);
}