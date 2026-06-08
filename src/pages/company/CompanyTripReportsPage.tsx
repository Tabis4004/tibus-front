import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { resolveCompanyStaffCompanyId } from "@/lib/supabase/owner-company";
import TripReportsPage from "@/pages/owner/analytics/trips/page.tsx";

const TRIP_REPORT_ROLES = ["comptable_compagnie", "controleur"] as const;

export default function CompanyTripReportsPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [companyId, setCompanyId] = useState<string | null | undefined>(undefined);

  const hasAccess = TRIP_REPORT_ROLES.some((role) => appUser.roles.includes(role));

  useEffect(() => {
    if (!appUser.isReady || appUser.isLoading) return;
    if (!hasAccess) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
      return;
    }
    if (!appUserId) return;

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
  }, [appUser.isReady, appUser.isLoading, hasAccess, appUserId, navigate, lng]);

  if (appUser.isLoading || companyId === undefined) {
    return (
      <div className="max-w-6xl mx-auto px-3 py-4">
        <Skeleton className="h-48 w-full" />
      </div>
    );
  }

  if (!companyId) {
    return (
      <div className="max-w-6xl mx-auto px-3 py-4 text-sm text-muted-foreground">
        Compagnie introuvable pour votre compte.
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto px-3 py-4 space-y-4">
      <div data-tour="company-staff-trips">
        <h1 className="text-xl font-extrabold">Rapports voyages</h1>
        <p className="text-sm text-muted-foreground">
          Suivez les départs, l&apos;occupation et les performances par trajet.
        </p>
      </div>
      <TripReportsPage />
    </div>
  );
}
