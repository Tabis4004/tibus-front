import { useMemo } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import { ArrowRightIcon, CompassIcon } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { getOnboardingAudience } from "@/lib/onboarding-audience.ts";
import { startExploreTour } from "@/lib/onboarding-events.ts";

type ExploreFeaturesButtonProps = {
  variant?: "button" | "menu-item" | "sidebar" | "icon" | "block";
  onTriggered?: () => void;
};

export default function ExploreFeaturesButton({
  variant = "button",
  onTriggered,
}: ExploreFeaturesButtonProps) {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const location = useLocation();
  const navigate = useNavigate();
  const appUser = useAppUser();

  const audience = useMemo(
    () => getOnboardingAudience(appUser.roles),
    [appUser.roles],
  );

  if (!appUser.isReady || appUser.isLoading) {
    return null;
  }

  const label = t("guide.explore_features", { defaultValue: "Explorer les fonctionnalités" });
  const description = t("home.explore_desc", {
    defaultValue: "Visite guidée des outils disponibles pour votre rôle",
  });

  const handleClick = () => {
    startExploreTour({
      pathname: location.pathname,
      audience,
      lng: lng ?? "fr",
      navigate,
    });
    onTriggered?.();
  };

  if (variant === "menu-item") {
    return (
      <button
        type="button"
        onClick={handleClick}
        className="relative flex w-full cursor-pointer select-none items-center rounded-sm px-2 py-1.5 text-sm outline-none transition-colors hover:bg-accent hover:text-accent-foreground"
      >
        <CompassIcon className="w-4 h-4 mr-2 text-primary" />
        {label}
      </button>
    );
  }

  if (variant === "sidebar") {
    return (
      <button
        type="button"
        onClick={handleClick}
        data-tour="owner-explore-features"
        className="flex w-full cursor-pointer items-center justify-center gap-2 rounded-xl border border-orange-300/60 bg-orange-100/80 dark:bg-orange-950/40 px-3 py-2.5 text-sm font-semibold text-orange-800 dark:text-orange-100 transition-colors hover:bg-orange-200/80 dark:hover:bg-orange-900/50"
      >
        <CompassIcon className="w-4 h-4" />
        {label}
      </button>
    );
  }

  if (variant === "block") {
    return (
      <button
        type="button"
        onClick={handleClick}
        data-tour="owner-explore-features"
        className="block w-full text-left cursor-pointer"
      >
        <div className="rounded-xl border border-primary/30 bg-primary/5 p-4 flex items-center gap-4 hover:border-primary/40 hover:shadow-sm transition-all group">
          <div className="w-12 h-12 rounded-xl bg-primary text-primary-foreground flex items-center justify-center shrink-0">
            <CompassIcon className="w-5 h-5" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-sm leading-snug">{label}</h3>
            <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{description}</p>
          </div>
          <ArrowRightIcon className="w-4 h-4 text-muted-foreground group-hover:text-primary shrink-0 transition-colors" />
        </div>
      </button>
    );
  }

  if (variant === "icon") {
    return (
      <Button
        type="button"
        variant="outline"
        size="icon"
        className="h-8 w-8 shrink-0 cursor-pointer"
        onClick={handleClick}
        title={label}
        aria-label={label}
      >
        <CompassIcon className="w-4 h-4" />
      </Button>
    );
  }

  return (
    <Button
      type="button"
      variant="outline"
      size="sm"
      className="cursor-pointer gap-1.5 text-xs h-8 max-sm:px-2"
      onClick={handleClick}
      title={label}
      data-tour="owner-explore-features"
    >
      <CompassIcon className="w-3.5 h-3.5" />
      <span className="max-sm:sr-only">{label}</span>
    </Button>
  );
}
