import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils.ts";
import { resolveConsoleTileStyle } from "@/lib/console-grid-tiles.ts";
import { useConsoleBlocksCustomize } from "@/components/console/ConsoleBlocksCustomizeContext.tsx";
import ConsoleTilePalettePicker from "@/components/console/ConsoleTilePalettePicker.tsx";

type ConsoleGridTileProps = {
  blockId?: string;
  tileIndex: number;
  icon: LucideIcon;
  label: string;
  value?: string;
  description?: string;
  className?: string;
  children?: ReactNode;
};

export default function ConsoleGridTile({
  blockId,
  tileIndex,
  icon: Icon,
  label,
  value,
  description,
  className,
  children,
}: ConsoleGridTileProps) {
  const customize = useConsoleBlocksCustomize();
  const resolvedId = blockId ?? `tile-${tileIndex}`;
  const finalStyle = customize
    ? customize.styleFor(resolvedId, tileIndex)
    : resolveConsoleTileStyle(tileIndex);

  const showPicker = Boolean(customize?.customizeMode && blockId);

  return (
    <div
      className={cn(
        "rounded-2xl border p-4 flex flex-col items-center justify-center text-center gap-2 min-h-[108px]",
        !showPicker && "hover:shadow-md transition-shadow",
        finalStyle.tile,
        finalStyle.border,
        className,
      )}
    >
      <div className={cn("w-11 h-11 rounded-2xl flex items-center justify-center shadow-sm", finalStyle.iconWrap)}>
        <Icon className={cn("w-5 h-5", finalStyle.icon)} />
      </div>
      {value != null ? (
        <>
          <p className="text-[11px] text-muted-foreground leading-tight">{label}</p>
          <p className={cn("font-black text-lg leading-none truncate max-w-full", finalStyle.title)}>{value}</p>
        </>
      ) : (
        <>
          <p className={cn("font-semibold text-sm leading-snug", finalStyle.title)}>{label}</p>
          {description ? (
            <p className="text-[11px] text-muted-foreground line-clamp-2 leading-snug">{description}</p>
          ) : null}
        </>
      )}
      {children}
      {showPicker && customize ? (
        <ConsoleTilePalettePicker
          blockId={resolvedId}
          selectedIndex={customize.paletteIndexFor(resolvedId, tileIndex)}
          defaultIndex={tileIndex}
          onSelect={(index) => customize.setBlockColor(resolvedId, index)}
          onReset={() => customize.resetBlockColor(resolvedId)}
        />
      ) : null}
    </div>
  );
}
