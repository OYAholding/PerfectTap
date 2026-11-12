// Username system — backed by playerService

import { getCachedProfile } from "./playerService";

export function getUsername() {
  const p = getCachedProfile();
  return p?.username || "";
}

export function hasUsername() {
  return !!getUsername();
}