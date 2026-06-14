import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { BookOpenIcon } from "lucide-react";
import { useAuth } from "@/hooks/use-auth.ts";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { getManualNavItems } from "@/lib/manual-nav.ts";
import { Button } from "@/components/ui/button.tsx";
import { cn } from "@/lib/utils.ts";

type ManualNavLinksProps = {
  variant?: "header" | "compact";
  className?: string;
};

export default function ManualNavLinks({ variant = "header", className }: ManualNavLinksProps) {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const { isAuthenticated } = useAuth();
  const appUser = useAppUser();
  const locale = lng ?? "fr";

  const items = getManualNavItems({
    roles: appUser.isReady ? appUser.roles : [],
    isSuperAdmin: appUser.isReady ? appUser.isSuperAdmin : false,
    isAuthenticated,
  });

  if (items.length === 0) return null;

  if (variant === "compact" && items.length === 1) {
    const item = items[0];
    return (
      <Button variant="ghost" size="sm" className={cn("gap-1.5 h-8 text-xs", className)} asChild>
        <Link to={`/${locale}${item.toSuffix}`}>
          <BookOpenIcon className="w-3.5 h-3.5" />
          <span className="max-sm:sr-only">
            {t(item.labelKey, { defaultValue: item.labelDefault })}
          </span>
        </Link>
      </Button>
    );
  }

  return (
    <div className={cn("flex items-center gap-1", className)}>
      {items.map((item) => (
        <Button key={item.toSuffix} variant="ghost" size="sm" className="gap-1.5 h-8 text-xs" asChild>
          <Link to={`/${locale}${item.toSuffix}`}>
            <BookOpenIcon className="w-3.5 h-3.5" />
            <span className="max-sm:sr-only">
              {t(item.labelKey, { defaultValue: item.labelDefault })}
            </span>
          </Link>
        </Button>
      ))}
    </div>
  );
}
