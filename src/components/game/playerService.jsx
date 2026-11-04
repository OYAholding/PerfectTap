// Central player data service
// Syncs player data between localStorage (fast reads) and server (persistence + uniqueness)

import { base44 } from "@/api/base44Client";

const PROFILE_CACHE_KEY = "perfecttap_profile_cache";
const PROFILE_ID_KEY = "perfecttap_profile_id";

let profileCache = null;

function getDefaultProfile() {
  return {
    username: "",
    avatar: "😊",
    coins: 0,
    best_classic: 0,
    best_endless: 0,
    best_timed: 0,
    best_sudden: 0,
    best_combofrenzy: 0,
    stats: {
      totalGames: 0, totalScore: 0, highestCombo: 0,
      totalDuels: 0, duelWins: 0, duelLosses: 0, duelTies: 0,
      favoriteMode: "classic", modeCounts: {},
      totalCoinsEarned: 0, questsCompleted: 0, perfectTaps: 0, totalTaps: 0,
    },
    owned_items: [],
    equipped: {},
    theme: "default",
    no_ads: false,
    score_history: [],
    daily_rewards: null,
    quest_data: null,
    friends: [],
    friend_code: "",
    challenges_done: [],
    active_challenge: "",
    boost: null,
    sound_enabled: true,
    music_enabled: true,
    haptics_enabled: true,
    recent_matches: [],
  };
}

// Load profile from server, cache locally
let loadPromise = null;
export async function loadProfile() {
  // Deduplicate concurrent calls (e.g. multiple pages calling loadProfile at once)
  if (loadPromise) return loadPromise;
  loadPromise = _doLoadProfile();
  const result = await loadPromise;
  loadPromise = null;
  return result;
}

async function _doLoadProfile() {
  // Fetch user email and profiles in parallel when possible
  const user = await base44.auth.me();
  const profiles = await base44.entities.PlayerProfile.filter({ created_by: user.email });
  if (profiles.length > 0) {
    const p = profiles[0];
    profileCache = { ...getDefaultProfile(), ...p };

    // Migrate old friends format [{name, code}] → [profileId strings]
    if (Array.isArray(profileCache.friends) && profileCache.friends.length > 0 && typeof profileCache.friends[0] === "object") {
      profileCache.friends = [];
    }

    // Ensure avatar field exists
    if (!profileCache.avatar) profileCache.avatar = "😊";

    localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profileCache));
    localStorage.setItem(PROFILE_ID_KEY, p.id);
    return profileCache;
  }
  return null;
}

// Get cached profile (sync, for fast reads during gameplay)
export function getCachedProfile() {
  if (profileCache) return profileCache;
  const raw = localStorage.getItem(PROFILE_CACHE_KEY);
  if (raw) {
    profileCache = JSON.parse(raw);
    return profileCache;
  }
  return null;
}

// Get profile ID
export function getProfileId() {
  const cached = getCachedProfile();
  if (cached?.id) return cached.id;
  return localStorage.getItem(PROFILE_ID_KEY);
}

// Check if username is unique
// Note: This queries across all profiles by username. Base44 entity filter
// returns only matching records. We compare IDs to allow self-rename.
export async function isUsernameAvailable(username) {
  const existing = await base44.entities.PlayerProfile.filter({ username });
  const myId = getProfileId();
  // Allow own username
  return existing.length === 0 || (existing.length === 1 && existing[0].id === myId);
}

// Create new profile with username
export async function createProfile(username) {
  const friendCode = generateFriendCode();
  const data = {
    ...getDefaultProfile(),
    username,
    friend_code: friendCode,
  };
  delete data.id;
  const created = await base44.entities.PlayerProfile.create(data);
  profileCache = { ...data, id: created.id };
  localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profileCache));
  localStorage.setItem(PROFILE_ID_KEY, created.id);
  return profileCache;
}

// Update profile on server + cache
export async function saveProfile(updates) {
  // First try fresh load to ensure we have a valid ID
  let freshProfile = await _doLoadProfile();
  let id = getProfileId();
  
  if (!id || !freshProfile) {
    // Profile doesn't exist on server — create a new one
    const username = updates.username || getCachedProfile()?.username || "";
    if (username) {
      await createProfile(username);
      // Apply any extra updates beyond username
      const { username: _, ...rest } = updates;
      if (Object.keys(rest).length > 0) {
        id = getProfileId();
        if (id) {
          profileCache = { ...getCachedProfile(), ...rest };
          localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profileCache));
          await base44.entities.PlayerProfile.update(id, rest);
        }
      }
      return;
    }
    return;
  }
  
  // Merge into cache
  profileCache = { ...getCachedProfile(), ...updates };
  localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profileCache));
  
  // Save to server
  await base44.entities.PlayerProfile.update(id, updates);
}

// Quick save — updates cache immediately, debounces server save
let saveTimer = null;
let pendingUpdates = {};

export function quickSave(updates) {
  // Update cache immediately
  profileCache = { ...getCachedProfile(), ...updates };
  localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profileCache));
  
  // Accumulate pending updates
  pendingUpdates = { ...pendingUpdates, ...updates };
  
  // Debounce server save (2 seconds)
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const id = getProfileId();
    if (id && Object.keys(pendingUpdates).length > 0) {
      base44.entities.PlayerProfile.update(id, pendingUpdates);
      pendingUpdates = {};
    }
  }, 2000);
}

// Force flush pending saves (call before navigating away from game)
export async function flushSave() {
  clearTimeout(saveTimer);
  const id = getProfileId();
  if (id && Object.keys(pendingUpdates).length > 0) {
    await base44.entities.PlayerProfile.update(id, pendingUpdates);
    pendingUpdates = {};
  }
}

// Auto-flush on page unload to prevent data loss
if (typeof window !== "undefined") {
  window.addEventListener("beforeunload", () => {
    const id = getProfileId();
    if (id && Object.keys(pendingUpdates).length > 0) {
      // Use sendBeacon or synchronous approach for reliability
      const payload = JSON.stringify(pendingUpdates);
      try {
        // Best effort — update cache so next load picks up latest
        localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profileCache));
      } catch (e) {}
    }
  });
  
  // Also flush on visibility change (tab switch on mobile)
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      const id = getProfileId();
      if (id && Object.keys(pendingUpdates).length > 0) {
        base44.entities.PlayerProfile.update(id, pendingUpdates);
        pendingUpdates = {};
      }
    }
  });
}

// Check if player has a profile
export function hasProfile() {
  return !!getProfileId();
}

// Has username set
export function hasUsername() {
  const p = getCachedProfile();
  return p && p.username && p.username.length > 0;
}

export function getUsername() {
  const p = getCachedProfile();
  return p?.username || "";
}

function generateFriendCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

// Migrate old localStorage data to profile (one-time)
export async function migrateLocalData() {
  const profile = getCachedProfile();
  if (!profile) return;
  
  // Only migrate if profile has 0 coins and localStorage has data
  const oldCoins = parseInt(localStorage.getItem("perfecttap_coins") || "0");
  if (oldCoins > 0 && profile.coins === 0) {
    const updates = {};
    updates.coins = oldCoins;
    updates.best_classic = parseInt(localStorage.getItem("perfecttap_best") || "0");
    updates.best_endless = parseInt(localStorage.getItem("perfecttap_best_endless") || "0");
    updates.best_timed = parseInt(localStorage.getItem("perfecttap_best_timed") || "0");
    updates.best_sudden = parseInt(localStorage.getItem("perfecttap_best_sudden") || "0");
    updates.best_combofrenzy = parseInt(localStorage.getItem("perfecttap_best_combofrenzy") || "0");
    
    const oldStats = localStorage.getItem("perfecttap_stats");
    if (oldStats) updates.stats = JSON.parse(oldStats);
    
    const oldOwned = localStorage.getItem("perfecttap_owned_items");
    if (oldOwned) updates.owned_items = JSON.parse(oldOwned);
    
    const oldEquipped = localStorage.getItem("perfecttap_equipped");
    if (oldEquipped) updates.equipped = JSON.parse(oldEquipped);
    
    const oldHistory = localStorage.getItem("perfecttap_history");
    if (oldHistory) updates.score_history = JSON.parse(oldHistory);
    
    const oldNoAds = localStorage.getItem("perfecttap_no_ads");
    if (oldNoAds === "true") updates.no_ads = true;
    
    const oldTheme = localStorage.getItem("perfecttap_theme");
    if (oldTheme) updates.theme = oldTheme;
    
    const oldFriends = localStorage.getItem("perfecttap_friends");
    if (oldFriends) updates.friends = JSON.parse(oldFriends);
    
    const oldChallenges = localStorage.getItem("perfecttap_challenges_done");
    if (oldChallenges) updates.challenges_done = JSON.parse(oldChallenges);
    
    await saveProfile(updates);
  }
}