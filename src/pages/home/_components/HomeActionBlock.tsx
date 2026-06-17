import { Children, cloneElement, isValidElement, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils.ts";
import { consoleTileStyle } from "@/lib/console-grid-tiles.ts";

type Props = {
  to: string;
  title: string;
  description: string;
  icon: LucideIcon;
  highlighted?: boolean;
  tour?: string;
  tileIndex?: number;
};

export function HomeActionBlock({
  to,
  title,
  description,
  icon: Icon,
  highlighted,
  tour,
  tileIndex = 0,
}: Props) {
  const style = consoleTileStyle(tileIndex);

  return (
    <Link to={to} className="block h-full" data-tour={tour}>
      <div
        className={cn(
          "rounded-2xl border p-4 flex flex-col items-center justify-center text-center gap-2 min-h-[108px] h-full",
          "hover:shadow-md transition-shadow",
          style.tile,
          style.border,
          highlighted && "ring-2 ring-primary/35",
        )}
      >
        <div className={cn("w-11 h-11 rounded-2xl flex items-center justify-center shadow-sm", style.iconWrap)}>
          <Icon className={cn("w-5 h-5", style.icon)} />
        </div>
        <h3 className={cn("font-semibold text-sm leading-snug", style.title)}>{title}</h3>
        <p className="text-[11px] text-muted-foreground line-clamp-2 leading-snug">{description}</p>
      </div>
    </Link>
  );
}

type HomeBlockSectionProps = {
  title: string;
  children: ReactNode;
};

export function HomeBlockSection({ title, children }: HomeBlockSectionProps) {
  const items = Children.toArray(children).filter(Boolean);

  return (
    <div className="space-y-2">
      <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider px-1">
        {title}
      </h2>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        {items.map((child, index) =>
          isValidElement(child)
            ? cloneElement(child as React.ReactElement<{ tileIndex?: number }>, { tileIndex: index })
            : child,
        )}
      </div>
    </div>
  );
}
