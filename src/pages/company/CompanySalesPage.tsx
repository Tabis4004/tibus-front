import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  resolveCompanyStaffCompanyId,
  COMPANY_STAFF_ROLE_NAMES,
} from "@/lib/supabase/owner-company";
import ExploreFeaturesButton from "@/components/onboarding/ExploreFeaturesButton.tsx";
import CompanySalesLedger from "@/pages/owner/_components/CompanySalesLedger.tsx";

const CANCEL_ROLES = ["owner", "vendeur"] as const;

export default function CompanyStaffSalesPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [companyId, setCompanyId] = useState<string | null | undefined>(undefined);

  const hasStaffAccess = COMPANY_STAFF_ROLE_NAMES.some((role) => appUser.roles.includes(role));
  const canCancel = CANCEL_ROLES.some((role) => appUser.roles.includes(role));

  useEffect(() => {
    if (!appUser.isReady || appUser.isLoading) return;
    if (!hasStaffAccess) {
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
  }, [appUser.isReady, appUser.isLoading, hasStaffAccess, appUserId, navigate, lng]);

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
      <div data-tour="company-staff-sales" className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-extrabold">Ventes compagnie</h1>
          <p className="text-sm text-muted-foreground">
            Journal des ventes guichet et en ligne pour votre compagnie.
          </p>
        </div>
        <ExploreFeaturesButton variant="icon" />
      </div>
      <CompanySalesLedger companyId={companyId} canCancel={canCancel} />
    </div>
  );
}
