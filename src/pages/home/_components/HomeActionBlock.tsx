import { Link } from "react-router-dom";
import { ArrowRightIcon, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils.ts";

type Props = {
  to: string;
  title: string;
  description: string;
  icon: LucideIcon;
  highlighted?: boolean;
  tour?: string;
};

export function HomeActionBlock({
  to,
  title,
  description,
  icon: Icon,
  highlighted,
  tour,
}: Props) {
  return (
    <Link to={to} className="block" data-tour={tour}>
      <div
        className={cn(
          "rounded-xl border bg-card p-4 flex items-center gap-4 hover:border-primary/40 hover:shadow-sm transition-all group",
          highlighted && "border-primary/30 bg-primary/5",
        )}
      >
        <div
          className={cn(
            "w-12 h-12 rounded-xl flex items-center justify-center shrink-0",
            highlighted ? "bg-primary text-primary-foreground" : "bg-primary/10",
          )}
        >
          <Icon className={cn("w-5 h-5", !highlighted && "text-primary")} />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-sm leading-snug">{title}</h3>
          <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{description}</p>
        </div>
        <ArrowRightIcon className="w-4 h-4 text-muted-foreground group-hover:text-primary shrink-0 transition-colors" />
      </div>
    </Link>
  );
}

type HomeBlockSectionProps = {
  title: string;
  children: React.ReactNode;
};

export function HomeBlockSection({ title, children }: HomeBlockSectionProps) {
  return (
    <div className="space-y-2">
      <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider px-1">
        {title}
      </h2>
      <div className="space-y-3">{children}</div>
    </div>
  );
}
