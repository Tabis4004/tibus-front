import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  resolveCompanyStaffCompanyId,
  COMPANY_STAFF_ROLE_NAMES,
} from "@/lib/supabase/owner-company";
import GuaranteeFundPanel from "@/pages/owner/_components/GuaranteeFundPanel.tsx";

export default function CompanyGuaranteeFundPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [companyId, setCompanyId] = useState<string | null | undefined>(undefined);

  const hasStaffAccess = COMPANY_STAFF_ROLE_NAMES.some((role) => appUser.roles.includes(role));
  const canValidate =
    appUser.roles.includes("owner") || appUser.roles.includes("comptable_compagnie");
  const canConfigureNegative = appUser.roles.includes("owner");

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
      <div className="max-w-5xl mx-auto px-3 py-4 space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-28 w-full" />
      </div>
    );
  }

  if (!companyId) {
    return (
      <div className="max-w-5xl mx-auto px-3 py-4 text-sm text-muted-foreground">
        Compagnie introuvable pour votre compte.
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto px-3 py-4 space-y-4">
      <div>
        <h1 className="text-xl font-extrabold">Fond de garantie</h1>
        <p className="text-sm text-muted-foreground">
          Solde et validation des dépôts plateforme.
        </p>
      </div>
      <GuaranteeFundPanel
        companyId={companyId}
        canValidateDeposits={canValidate}
        canConfigureNegative={canConfigureNegative}
      />
    </div>
  );
}
