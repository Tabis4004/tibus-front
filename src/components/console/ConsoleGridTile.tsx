import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils.ts";
import { consoleTileStyle } from "@/lib/console-grid-tiles.ts";

type ConsoleGridTileProps = {
  tileIndex: number;
  icon: LucideIcon;
  label: string;
  value?: string;
  description?: string;
  className?: string;
  children?: ReactNode;
};

export default function ConsoleGridTile({
  tileIndex,
  icon: Icon,
  label,
  value,
  description,
  className,
  children,
}: ConsoleGridTileProps) {
  const style = consoleTileStyle(tileIndex);

  return (
    <div
      className={cn(
        "rounded-2xl border p-4 flex flex-col items-center justify-center text-center gap-2 min-h-[108px]",
        "hover:shadow-md transition-shadow",
        style.tile,
        style.border,
        className,
      )}
    >
      <div className={cn("w-11 h-11 rounded-2xl flex items-center justify-center shadow-sm", style.iconWrap)}>
        <Icon className={cn("w-5 h-5", style.icon)} />
      </div>
      {value != null ? (
        <>
          <p className="text-[11px] text-muted-foreground leading-tight">{label}</p>
          <p className={cn("font-black text-lg leading-none truncate max-w-full", style.title)}>{value}</p>
        </>
      ) : (
        <>
          <p className={cn("font-semibold text-sm leading-snug", style.title)}>{label}</p>
          {description ? (
            <p className="text-[11px] text-muted-foreground line-clamp-2 leading-snug">{description}</p>
          ) : null}
        </>
      )}
      {children}
    </div>
  );
}
