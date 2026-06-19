import { createContext, useContext, type ReactNode } from "react";
import type { ConsoleTileStyle } from "@/lib/console-grid-tiles.ts";

export type ConsoleBlocksCustomizeValue = {
  customizeMode: boolean;
  styleFor: (blockId: string, defaultIndex: number) => ConsoleTileStyle;
  paletteIndexFor: (blockId: string, defaultIndex: number) => number;
  setBlockColor: (blockId: string, paletteIndex: number) => void;
  resetBlockColor: (blockId: string) => void;
};

const ConsoleBlocksCustomizeContext = createContext<ConsoleBlocksCustomizeValue | null>(null);

export function ConsoleBlocksCustomizeProvider({
  value,
  children,
}: {
  value: ConsoleBlocksCustomizeValue;
  children: ReactNode;
}) {
  return (
    <ConsoleBlocksCustomizeContext.Provider value={value}>
      {children}
    </ConsoleBlocksCustomizeContext.Provider>
  );
}

export function useConsoleBlocksCustomize(): ConsoleBlocksCustomizeValue | null {
  return useContext(ConsoleBlocksCustomizeContext);
}
