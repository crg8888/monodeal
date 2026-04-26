// Manages player identity in localStorage.
//
// Monodeal has no auth. The first time a visitor enters a name, the server
// issues a player_id + player_token. Both are persisted in localStorage so a
// page refresh recovers the same seat. On Full Reset the server invalidates
// tokens; the client should call clearIdentity() once it detects a stale token.
//
// localStorage may throw (Safari private mode, quota, disabled storage) so all
// access is wrapped in try/catch and falls back to a module-level in-memory
// copy that lasts for the lifetime of the tab.

export interface Identity {
  player_id: string;
  player_token: string;
  name: string; // last-known name, for prefilling the name entry on a fresh tab
}

const IDENTITY_KEY = "monodeal_identity";
const NAME_KEY = "monodeal_last_name";

let memoryFallback: Identity | null = null;
let memoryName = "";

export function getIdentity(): Identity | null {
  try {
    const raw = localStorage.getItem(IDENTITY_KEY);
    if (!raw) return memoryFallback;
    const parsed = JSON.parse(raw) as Partial<Identity>;
    if (
      typeof parsed?.player_id === "string" &&
      typeof parsed?.player_token === "string" &&
      typeof parsed?.name === "string"
    ) {
      return {
        player_id: parsed.player_id,
        player_token: parsed.player_token,
        name: parsed.name,
      };
    }
    return null;
  } catch {
    return memoryFallback;
  }
}

export function setIdentity(identity: Identity): void {
  memoryFallback = identity;
  try {
    localStorage.setItem(IDENTITY_KEY, JSON.stringify(identity));
  } catch {
    // Storage unavailable — memoryFallback is the source of truth this tab.
  }
  // Keep the cached name in sync so a future fresh tab can prefill it.
  setCachedName(identity.name);
}

export function clearIdentity(): void {
  memoryFallback = null;
  try {
    localStorage.removeItem(IDENTITY_KEY);
  } catch {
    // ignore
  }
}

export function getCachedName(): string {
  try {
    const raw = localStorage.getItem(NAME_KEY);
    if (typeof raw === "string") return raw;
    return memoryName;
  } catch {
    return memoryName;
  }
}

export function setCachedName(name: string): void {
  memoryName = name;
  try {
    localStorage.setItem(NAME_KEY, name);
  } catch {
    // ignore
  }
}

export function isHost(
  identity: Identity | null,
  hostPlayerId: string | null,
): boolean {
  return !!identity && !!hostPlayerId && identity.player_id === hostPlayerId;
}
