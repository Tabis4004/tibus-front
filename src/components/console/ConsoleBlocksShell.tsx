import { useMemo, type ReactNode } from "react";
import { useConsoleTilePreferences } from "@/hooks/use-console-tile-preferences.ts";
import type { ConsoleTileSurface } from "@/lib/console-tile-preferences.ts";
import { ConsoleBlocksCustomizeProvider } from "@/components/console/ConsoleBlocksCustomizeContext.tsx";
import ConsoleBlocksCustomizeBar from "@/components/console/ConsoleBlocksCustomizeBar.tsx";

type Props = {
  userId: string | null;
  surface: ConsoleTileSurface;
  children: ReactNode;
  showToolbar?: boolean;
  className?: string;
};

export default function ConsoleBlocksShell({
  userId,
  surface,
  children,
  showToolbar = true,
  className,
}: Props) {
  const prefs = useConsoleTilePreferences(userId, surface);

  const contextValue = useMemo(
    () => ({
      customizeMode: prefs.customizeMode,
      styleFor: prefs.styleFor,
      paletteIndexFor: prefs.paletteIndexFor,
      setBlockColor: prefs.setBlockColor,
      resetBlockColor: prefs.resetBlockColor,
    }),
    [prefs],
  );

  return (
    <ConsoleBlocksCustomizeProvider value={contextValue}>
      {showToolbar ? (
        <ConsoleBlocksCustomizeBar
          active={prefs.customizeMode}
          onToggle={() => prefs.setCustomizeMode((v) => !v)}
          className={className}
        />
      ) : null}
      {children}
    </ConsoleBlocksCustomizeProvider>
  );
}
