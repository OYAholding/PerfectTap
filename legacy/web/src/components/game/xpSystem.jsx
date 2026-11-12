// XP & Level system — reads/writes through playerService cache
import { getCachedProfile, quickSave } from "./playerService";

// XP required per level — scales up
export function xpForLevel(level) {
  return Math.floor(100 * Math.pow(1.15, level - 1));
}

export function getXP() {
  const p = getCachedProfile();
  return p?.xp || 0;
}

export function getLevel() {
  const p = getCachedProfile();
  return p?.level || 1;
}

export function getLevelProgress() {
  const xp = getXP();
  const level = getLevel();
  const needed = xpForLevel(level);
  return { xp, level, needed, progress: Math.min(1, xp / needed) };
}

// Award XP and handle level ups — returns { xpGained, newLevel, leveledUp }
export function awardXP(amount) {
  if (amount <= 0) return { xpGained: 0, newLevel: getLevel(), leveledUp: false };

  let xp = getXP();
  let level = getLevel();
  xp += amount;
  let leveledUp = false;

  // Check for level ups
  while (xp >= xpForLevel(level)) {
    xp -= xpForLevel(level);
    level += 1;
    leveledUp = true;
  }

  quickSave({ xp, level });
  return { xpGained: amount, newLevel: level, leveledUp };
}

// Calculate XP earned from a game
export function calcGameXP(score, maxCombo, mode) {
  let base = Math.floor(score / 20);
  const comboBonus = Math.floor(maxCombo / 2);
  const modeBonus = mode === "sudden_death" ? 15 : mode === "combo_frenzy" ? 10 : mode === "duel" ? 20 : 5;
  return Math.max(5, base + comboBonus + modeBonus);
}

// Level reward unlocks
export const LEVEL_REWARDS = [
  { level: 3, type: "coins", amount: 100, label: "100 Coins" },
  { level: 5, type: "mode", id: "endless", label: "Endless Mode" },
  { level: 7, type: "coins", amount: 200, label: "200 Coins" },
  { level: 10, type: "theme", id: "ice", label: "Arctic Theme" },
  { level: 15, type: "coins", amount: 500, label: "500 Coins" },
  { level: 20, type: "avatar", id: "av_wizard", label: "Wizard Avatar" },
  { level: 25, type: "coins", amount: 1000, label: "1000 Coins" },
  { level: 30, type: "theme", id: "galaxy", label: "Galaxy Theme" },
  { level: 40, type: "coins", amount: 2000, label: "2000 Coins" },
  { level: 50, type: "badge", id: "badge_legend", label: "Legend Badge" },
];