import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import LoyaltySettings from "./_components/LoyaltySettings.tsx";

export default function LoyaltyPage() {
  const { selectedCompany, isLoading, isReady } = useOwnerCompany();

  if (!isReady || isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }

  if (!selectedCompany) {
    return <p className="text-sm text-muted-foreground p-6">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-4xl mx-auto">
      <LoyaltySettings key={selectedCompany.id} companyId={selectedCompany.id} />
    </div>
  );
}
