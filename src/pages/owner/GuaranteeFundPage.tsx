import { useAppUser } from "@/hooks/use-app-user.ts";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import GuaranteeFundPanel from "./_components/GuaranteeFundPanel.tsx";

export default function GuaranteeFundPage() {
  const appUser = useAppUser();
  const { selectedCompany, isLoading, isReady } = useOwnerCompany();

  const canValidate =
    appUser.roles.includes("owner") || appUser.roles.includes("comptable_compagnie");
  const canConfigureNegative = appUser.roles.includes("owner");

  if (!isReady || isLoading || appUser.isLoading) {
    return (
      <div className="p-4 md:p-6 max-w-5xl mx-auto space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-28 w-full" />
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
        <h1 className="text-2xl font-extrabold tracking-tight">Fond de garantie</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Consultez le solde, validez les dépôts plateforme (avec relevé) et configurez le passage
          en solde négatif si nécessaire.
        </p>
      </div>
      <GuaranteeFundPanel
        key={selectedCompany.id}
        companyId={selectedCompany.id}
        canValidateDeposits={canValidate}
        canConfigureNegative={canConfigureNegative}
      />
    </div>
  );
}
