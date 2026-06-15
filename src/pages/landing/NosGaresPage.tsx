import { useEffect } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeftIcon } from "lucide-react";
import { useTranslation } from "react-i18next";
import AppHeader from "@/pages/layout/_components/AppHeader.tsx";
import BottomNav from "@/pages/layout/_components/BottomNav.tsx";
import { Button } from "@/components/ui/button.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useAuth } from "@/hooks/use-auth.ts";
import { canViewNetworkGaresMap } from "@/lib/gares-map-audience.ts";
import HomeStationsMap from "@/pages/landing/HomeStationsMap.tsx";

export default function NosGaresPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("common");
  const locale = lng ?? "fr";
  const { isAuthenticated } = useAuth();
  const appUser = useAppUser();

  const canView =
    !isAuthenticated ||
    (appUser.isReady && canViewNetworkGaresMap(appUser.roles, isAuthenticated));

  useEffect(() => {
    if (!isAuthenticated || !appUser.isReady || appUser.isLoading) return;
    if (!canViewNetworkGaresMap(appUser.roles, true)) {
      navigate(`/${locale}`, { replace: true });
    }
  }, [appUser.isReady, appUser.isLoading, appUser.roles, isAuthenticated, locale, navigate]);

  if (isAuthenticated && (!appUser.isReady || appUser.isLoading)) {
    return (
      <div className="min-h-svh bg-background flex items-center justify-center">
        <div className="h-8 w-8 rounded-full border-2 border-primary border-t-transparent animate-spin" />
      </div>
    );
  }

  if (isAuthenticated && !canView) {
    return null;
  }

  return (
    <div className="flex flex-col min-h-screen">
      <AppHeader />
      <main className="flex-1 pb-20 md:pb-0">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 pt-4">
          <Button variant="ghost" size="sm" asChild className="mb-2">
            <Link to={`/${locale}`}>
              <ArrowLeftIcon className="w-4 h-4 mr-1" />
              {t("nav.home", { defaultValue: "Accueil" })}
            </Link>
          </Button>
        </div>
        <HomeStationsMap />
      </main>
      {isAuthenticated ? <BottomNav /> : null}
    </div>
  );
}
