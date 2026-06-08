import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import CompanySalesLedger from "./_components/CompanySalesLedger.tsx";

export default function CompanySalesPage() {
  const { selectedCompany, isLoading, isReady } = useOwnerCompany();

  if (!isReady || isLoading) {
    return <Skeleton className="h-48 w-full" />;
  }

  if (!selectedCompany) {
    return <p className="text-sm text-muted-foreground p-6">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-6xl mx-auto">
      <CompanySalesLedger key={selectedCompany.id} companyId={selectedCompany.id} canCancel />
    </div>
  );
}
