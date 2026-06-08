import { useEffect, useState } from "react";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { getMyCompanySupabase, type OwnerCompany } from "@/lib/supabase/owner-company";
import GuaranteeFundPanel from "./_components/GuaranteeFundPanel.tsx";

export default function GuaranteeFundPage() {
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [company, setCompany] = useState<OwnerCompany | null | undefined>(undefined);

  const canValidate =
    appUser.roles.includes("owner") || appUser.roles.includes("comptable_compagnie");
  const canConfigureNegative = appUser.roles.includes("owner");

  useEffect(() => {
    if (!appUserId) return;
    let cancelled = false;
    void getMyCompanySupabase(appUserId)
      .then((row) => {
        if (!cancelled) setCompany(row);
      })
      .catch(() => {
        if (!cancelled) setCompany(null);
      });
    return () => {
      cancelled = true;
    };
  }, [appUserId]);

  if (company === undefined || appUser.isLoading) {
    return (
      <div className="p-4 md:p-6 max-w-5xl mx-auto space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (!company) {
    return <p className="p-6 text-sm text-muted-foreground">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-5xl mx-auto space-y-4">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">Fond de garantie</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Consultez le solde, validez les dépôts plateforme (avec relevé) et configurez le passage
          en solde négatif si nécessaire.
        </p>
      </div>
      <GuaranteeFundPanel
        companyId={company.id}
        canValidateDeposits={canValidate}
        canConfigureNegative={canConfigureNegative}
      />
    </div>
  );
}
