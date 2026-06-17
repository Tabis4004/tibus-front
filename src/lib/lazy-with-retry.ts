import { lazy, type ComponentType } from "react";

export function isChunkLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return (
    message.includes("Failed to fetch dynamically imported module") ||
    message.includes("Importing a module script failed") ||
    message.includes("error loading dynamically imported module")
  );
}

const CHUNK_RELOAD_KEY = "tibus-chunk-reload";

/** Recharge une fois après déploiement si un chunk lazy a un hash obsolète. */
export function lazyWithRetry<T extends ComponentType<unknown>>(
  factory: () => Promise<{ default: T }>,
) {
  return lazy(async () => {
    try {
      return await factory();
    } catch (error) {
      if (isChunkLoadError(error) && !sessionStorage.getItem(CHUNK_RELOAD_KEY)) {
        sessionStorage.setItem(CHUNK_RELOAD_KEY, "1");
        window.location.reload();
        await new Promise(() => {});
      }
      throw error;
    }
  });
}
