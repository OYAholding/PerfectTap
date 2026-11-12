// Virtual currency system — reads/writes through playerService cache

import { getCachedProfile, quickSave } from "./playerService";

export function getCoins() {
  const p = getCachedProfile();
  return p?.coins || 0;
}

export function addCoins(amount) {
  if (amount <= 0) return getCoins();
  const current = getCoins();
  const next = current + amount;
  quickSave({ coins: next });
  return next;
}

export function spendCoins(amount) {
  if (amount <= 0) return false;
  const current = getCoins();
  if (current < amount) return false;
  quickSave({ coins: current - amount });
  return true;
}

export function getOwnedItems() {
  const p = getCachedProfile();
  return p?.owned_items || [];
}

export function addOwnedItem(itemId) {
  const owned = getOwnedItems();
  if (!owned.includes(itemId)) {
    owned.push(itemId);
    quickSave({ owned_items: owned });
  }
}

export function getEquippedItems() {
  const p = getCachedProfile();
  return p?.equipped || {};
}

export function equipItem(category, itemId) {
  const equipped = getEquippedItems();
  equipped[category] = itemId;
  quickSave({ equipped });
}

// Calculate coins earned from a game session
// ONLY Classic mode earns coins — halved for balance
export function calcGameCoins(score, maxCombo, mode) {
  if (mode !== "classic") return 0;
  let base = Math.floor(score / 40);
  const comboBonus = maxCombo >= 10 ? 10 : maxCombo >= 5 ? 5 : 0;
  return Math.max(1, base + comboBonus);
}

// IAP: check if ads are removed
export function isAdsRemoved() {
  const p = getCachedProfile();
  return p?.no_ads || false;
}

export function setAdsRemoved() {
  quickSave({ no_ads: true });
}

// IAP coin packs — prices are placeholders for App Store
export const COIN_PACKS = [
  { id: "pack_small",  coins: 500,  price: "$0.99",  label: "Starter Pack",  icon: "🪙", popular: false },
  { id: "pack_medium", coins: 1500, price: "$2.99",  label: "Value Pack",    icon: "💰", popular: true },
  { id: "pack_large",  coins: 5000, price: "$7.99",  label: "Mega Pack",     icon: "💎", popular: false },
  { id: "pack_huge",   coins: 15000,price: "$19.99", label: "Ultimate Pack", icon: "👑", popular: false },
];

export const REMOVE_ADS_PRICE = "$3.99";