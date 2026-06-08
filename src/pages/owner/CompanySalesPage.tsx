import { useEffect, useState } from "react";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { getMyCompanySupabase, type OwnerCompany } from "@/lib/supabase/owner-company";
import CompanySalesLedger from "./_components/CompanySalesLedger.tsx";

export default function CompanySalesPage() {
  const { appUserId } = useSupabaseAuth();
  const [company, setCompany] = useState<OwnerCompany | null | undefined>(undefined);

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

  if (company === undefined) {
    return <Skeleton className="h-48 w-full" />;
  }

  if (!company) {
    return <p className="text-sm text-muted-foreground p-6">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-6xl mx-auto">
      <CompanySalesLedger companyId={company.id} canCancel />
    </div>
  );
}
