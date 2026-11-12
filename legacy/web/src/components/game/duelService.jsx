// Duel creation & score submission via backend functions
import { base44 } from "@/api/base44Client";

function generateCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

// Create a duel through the backend (rate-limited, validated)
export async function createDuelViaBackend(hostName) {
  const code = generateCode();
  const response = await base44.functions.invoke("createDuel", {
    code,
    host_name: hostName,
  });
  return response.data; // { id, code } or { error }
}

// Join a duel through the backend (validated)
export async function joinDuelViaBackend(code, guestName) {
  const response = await base44.functions.invoke("joinDuel", {
    code,
    guest_name: guestName,
  });
  return response.data; // { success, duelId, hostName } or { error }
}

// Submit a game score through the backend (validated)
export async function submitScoreViaBackend({ mode, score, maxCombo, duelId, duelRole }) {
  const response = await base44.functions.invoke("submitScore", {
    mode,
    score,
    maxCombo,
    duelId: duelId || undefined,
    duelRole: duelRole || undefined,
  });
  return response.data; // { success, validated_score } or { error }
}