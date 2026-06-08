import { useMemo } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import { CompassIcon } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { getOnboardingAudience } from "@/lib/onboarding-audience.ts";
import { startExploreTour } from "@/lib/onboarding-events.ts";

type ExploreFeaturesButtonProps = {
  variant?: "button" | "menu-item" | "sidebar" | "icon";
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

  if (!appUser.isReady || appUser.isLoading || !appUser.profileCompleted) {
    return null;
  }

  const label = t("guide.explore_features", { defaultValue: "Explorer les fonctionnalités" });

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
        className="flex w-full cursor-pointer items-center justify-center gap-2 rounded-xl border border-sidebar-primary/30 bg-sidebar-primary/10 px-3 py-2.5 text-sm font-semibold text-sidebar-primary transition-colors hover:bg-sidebar-primary/20"
      >
        <CompassIcon className="w-4 h-4" />
        {label}
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
    >
      <CompassIcon className="w-3.5 h-3.5" />
      <span className="max-sm:sr-only">{label}</span>
    </Button>
  );
}
