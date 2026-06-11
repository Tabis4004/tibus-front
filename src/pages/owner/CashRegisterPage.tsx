import { useAppUser } from "@/hooks/use-app-user.ts";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import StationCashOverviewPanel from "./_components/StationCashOverviewPanel.tsx";
import StationCashReversalsPanel from "@/pages/company/_components/StationCashReversalsPanel.tsx";

export default function CashRegisterPage() {
  const appUser = useAppUser();
  const { selectedCompany, isLoading, isReady } = useOwnerCompany();

  const canValidate = appUser.roles.includes("owner");

  if (!isReady || isLoading || appUser.isLoading) {
    return (
      <div className="p-4 md:p-6 max-w-5xl mx-auto space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-40 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (!selectedCompany) {
    return <p className="p-6 text-sm text-muted-foreground">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-5xl mx-auto space-y-4">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">Caisse physique guichet</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Suivi des espèces en gare, caisses ouvertes et validation des reversements comptables.
        </p>
      </div>
      <StationCashOverviewPanel key={selectedCompany.id} companyId={selectedCompany.id} />
      <StationCashReversalsPanel
        key={`${selectedCompany.id}-reversals`}
        companyId={selectedCompany.id}
        canValidate={canValidate}
      />
    </div>
  );
}
