export type ConsoleTileSurface = "home" | "owner" | "admin";

const STORAGE_VERSION = 1;

type StoredPrefs = {
  v: number;
  colors: Record<string, number>;
};

function storageKey(userId: string, surface: ConsoleTileSurface): string {
  return `tibus:console-tile-colors:${STORAGE_VERSION}:${surface}:${userId}`;
}

export function loadConsoleTileColors(
  userId: string,
  surface: ConsoleTileSurface,
): Record<string, number> {
  if (!userId || typeof window === "undefined") return {};
  try {
    const raw = localStorage.getItem(storageKey(userId, surface));
    if (!raw) return {};
    const parsed = JSON.parse(raw) as StoredPrefs;
    if (parsed?.v !== STORAGE_VERSION || !parsed.colors) return {};
    return parsed.colors;
  } catch {
    return {};
  }
}

export function saveConsoleTileColors(
  userId: string,
  surface: ConsoleTileSurface,
  colors: Record<string, number>,
): void {
  if (!userId || typeof window === "undefined") return;
  const payload: StoredPrefs = { v: STORAGE_VERSION, colors };
  localStorage.setItem(storageKey(userId, surface), JSON.stringify(payload));
}

export function blockIdFromPath(path: string): string {
  return path.replace(/^\/+/, "").replace(/\//g, "-") || "root";
}
