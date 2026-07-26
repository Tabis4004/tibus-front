import { Link, useParams } from "react-router-dom";
import { FileTextIcon } from "lucide-react";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Button } from "@/components/ui/button.tsx";
import ColisNaturesManager from "./_components/ColisNaturesManager.tsx";
import ColisFormBuilderPanel from "./_components/ColisFormBuilderPanel.tsx";

export default function ColisSettingsPage() {
  const { lng } = useParams<{ lng: string }>();
  const { selectedCompany, isLoading, isReady } = useOwnerCompany();

  if (!isReady || isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }

  if (!selectedCompany) {
    return <p className="text-sm text-muted-foreground p-6">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-4xl mx-auto space-y-4">
      <div className="flex justify-end">
        <Button asChild size="sm" variant="outline">
          <Link to={`/${lng ?? "fr"}/owner/analytics/trips?tab=colis`}>
            <FileTextIcon className="w-3.5 h-3.5 mr-1.5" />
            Manifeste colis (imprimer / exporter)
          </Link>
        </Button>
      </div>
      <ColisNaturesManager key={selectedCompany.id} companyId={selectedCompany.id} />
      <ColisFormBuilderPanel key={`${selectedCompany.id}-builder`} companyId={selectedCompany.id} />
    </div>
  );
}
