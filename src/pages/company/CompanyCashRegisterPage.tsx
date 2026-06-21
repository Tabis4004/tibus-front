import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  resolveCompanyStaffCompanyId,
  COMPANY_STAFF_ROLE_NAMES,
} from "@/lib/supabase/owner-company";
import { isGareCashValidatorRole } from "@/lib/owner-team-roles.ts";
import StationCashReversalsPanel from "@/pages/company/_components/StationCashReversalsPanel.tsx";

const CASH_REGISTER_ROLES = [...COMPANY_STAFF_ROLE_NAMES, "owner"] as const;

export default function CompanyCashRegisterPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [companyId, setCompanyId] = useState<string | null | undefined>(undefined);

  const hasAccess = CASH_REGISTER_ROLES.some((role) => appUser.roles.includes(role));
  const canValidate =
    appUser.roles.includes("owner")
    || appUser.roles.includes("comptable_compagnie")
    || appUser.roles.some((role) => isGareCashValidatorRole(role));

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
      <div className="max-w-6xl mx-auto px-3 py-4 space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-40 w-full" />
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
      <div data-tour="company-staff-cash">
        <h1 className="text-xl font-extrabold">Caisse physique guichet</h1>
        <p className="text-sm text-muted-foreground">
          En tant que comptable, vous validez ici les reversements remis par les vendeurs.
          Vous n&apos;ouvrez pas de caisse guichet — seuls les vendeurs ouvrent leur session du jour.
        </p>
      </div>
      <StationCashReversalsPanel companyId={companyId} canValidate={canValidate} />
    </div>
  );
}
