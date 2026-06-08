import { useEffect, useState } from "react";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { getMyCompanySupabase, type OwnerCompany } from "@/lib/supabase/owner-company";
import LoyaltySettings from "./_components/LoyaltySettings.tsx";

export default function LoyaltyPage() {
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
    return <Skeleton className="h-64 w-full" />;
  }

  if (!company) {
    return <p className="text-sm text-muted-foreground p-6">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-4xl mx-auto">
      <LoyaltySettings companyId={company.id} />
    </div>
  );
}
