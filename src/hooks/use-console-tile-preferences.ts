import { useCallback, useEffect, useMemo, useState } from "react";
import {
  loadConsoleTileColors,
  saveConsoleTileColors,
  type ConsoleTileSurface,
} from "@/lib/console-tile-preferences.ts";
import { resolveConsoleTileStyle } from "@/lib/console-grid-tiles.ts";

export function useConsoleTilePreferences(userId: string | null, surface: ConsoleTileSurface) {
  const [customizeMode, setCustomizeMode] = useState(false);
  const [colors, setColors] = useState<Record<string, number>>(() =>
    userId ? loadConsoleTileColors(userId, surface) : {},
  );

  useEffect(() => {
    setColors(userId ? loadConsoleTileColors(userId, surface) : {});
  }, [surface, userId]);

  const persist = useCallback(
    (next: Record<string, number>) => {
      setColors(next);
      if (userId) saveConsoleTileColors(userId, surface, next);
    },
    [surface, userId],
  );

  const setBlockColor = useCallback(
    (blockId: string, paletteIndex: number) => {
      persist({ ...colors, [blockId]: paletteIndex });
    },
    [colors, persist],
  );

  const resetBlockColor = useCallback(
    (blockId: string) => {
      const next = { ...colors };
      delete next[blockId];
      persist(next);
    },
    [colors, persist],
  );

  const styleFor = useCallback(
    (blockId: string, defaultIndex: number) =>
      resolveConsoleTileStyle(defaultIndex, colors, blockId),
    [colors],
  );

  const paletteIndexFor = useCallback(
    (blockId: string, defaultIndex: number) => colors[blockId] ?? defaultIndex,
    [colors],
  );

  return useMemo(
    () => ({
      customizeMode,
      setCustomizeMode,
      setBlockColor,
      resetBlockColor,
      styleFor,
      paletteIndexFor,
    }),
    [customizeMode, paletteIndexFor, resetBlockColor, setBlockColor, styleFor],
  );
}
