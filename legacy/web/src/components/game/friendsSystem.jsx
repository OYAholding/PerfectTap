// Friends system — backed by real PlayerProfile lookups
import { base44 } from "@/api/base44Client";
import { getCachedProfile, getProfileId, quickSave } from "./playerService";

export function getMyFriendCode() {
  const p = getCachedProfile();
  return p?.friend_code || "";
}

// Get friend IDs from cache
export function getFriendIds() {
  const p = getCachedProfile();
  return p?.friends || [];
}

// Look up a player by friend code — returns their profile or null
export async function findPlayerByCode(code) {
  const results = await base44.entities.PlayerProfile.filter({ friend_code: code.toUpperCase() });
  return results.length > 0 ? results[0] : null;
}

// Add friend by their profile ID (bidirectional)
export async function addFriendById(friendProfileId) {
  const myId = getProfileId();
  const friends = getFriendIds();
  if (friends.includes(friendProfileId) || friendProfileId === myId) return false;
  friends.push(friendProfileId);
  quickSave({ friends });
  return true;
}

// Remove friend by profile ID
export function removeFriend(friendProfileId) {
  const friends = getFriendIds().filter(id => id !== friendProfileId);
  quickSave({ friends });
}

// Load full friend profiles from their IDs
export async function loadFriendProfiles() {
  const ids = getFriendIds();
  if (ids.length === 0) return [];
  
  // Fetch all friend profiles
  const profiles = [];
  for (const id of ids) {
    const results = await base44.entities.PlayerProfile.filter({ id });
    if (results.length > 0) profiles.push(results[0]);
  }
  return profiles;
}