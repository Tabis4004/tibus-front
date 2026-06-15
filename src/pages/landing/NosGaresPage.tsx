import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeftIcon } from "lucide-react";
import { useTranslation } from "react-i18next";
import AppHeader from "@/pages/layout/_components/AppHeader.tsx";
import BottomNav from "@/pages/layout/_components/BottomNav.tsx";
import { Button } from "@/components/ui/button.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useAuth } from "@/hooks/use-auth.ts";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { resolveGaresMapScope } from "@/lib/gares-map-audience.ts";
import { resolveCompanyStaffCompanyId } from "@/lib/supabase/owner-company.ts";
import HomeStationsMap from "@/pages/landing/HomeStationsMap.tsx";

export default function NosGaresPage() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const locale = lng ?? "fr";
  const { isAuthenticated } = useAuth();
  const appUser = useAppUser();
  const { appUserId } = useSupabaseAuth();
  const [companyId, setCompanyId] = useState<string | null | undefined>(undefined);

  const scope = useMemo(() => {
    if (!isAuthenticated || !appUser.isReady || !appUserId) return "platform" as const;
    return resolveGaresMapScope(appUser.roles);
  }, [appUser.isReady, appUser.roles, appUserId, isAuthenticated]);

  useEffect(() => {
    if (scope !== "company" || !appUserId) {
      setCompanyId(null);
      return;
    }

    let cancelled = false;
    void resolveCompanyStaffCompanyId(appUserId)
      .then((id) => {
        if (!cancelled) setCompanyId(id);
      })
      .catch(() => {
        if (!cancelled) setCompanyId(null);
      });

    return () => {
      cancelled = true;
    };
  }, [scope, appUserId]);

  const companyReady = scope !== "company" || companyId !== undefined;

  return (
    <div className="flex flex-col min-h-screen">
      <AppHeader />
      <main className="flex-1 pb-20 md:pb-0">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 pt-4">
          <Button variant="ghost" size="sm" asChild className="mb-2">
            <Link to={isAuthenticated ? `/${locale}` : `/${locale}`}>
              <ArrowLeftIcon className="w-4 h-4 mr-1" />
              {t("nav.home", { defaultValue: "Accueil" })}
            </Link>
          </Button>
        </div>
        {companyReady ? (
          <HomeStationsMap scope={scope} companyId={companyId} />
        ) : null}
      </main>
      {isAuthenticated ? <BottomNav /> : null}
    </div>
  );
}
