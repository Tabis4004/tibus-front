import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useCompanyTicketReprint } from "@/hooks/use-company-ticket-reprint.tsx";
import { canReprintCounterTickets } from "@/lib/owner-console-modules.tsx";
import type { OwnerCompanyOption } from "@/lib/supabase/owner-company";
import CompanySalesLedger from "./_components/CompanySalesLedger.tsx";
import ColisSalesJournalPanel from "./_components/ColisSalesJournalPanel.tsx";

function CompanySalesPageContent({ company }: { company: OwnerCompanyOption }) {
  const appUser = useAppUser();
  const canReprint = canReprintCounterTickets(appUser.roles, appUser.isSuperAdmin);
  const { onReprint, reprintView, isReprinting } = useCompanyTicketReprint(company.id, company.name);

  if (isReprinting && reprintView) {
    return <div className="p-4 md:p-6 max-w-6xl mx-auto">{reprintView}</div>;
  }

  return (
    <div className="p-4 md:p-6 max-w-6xl mx-auto space-y-6">
      <CompanySalesLedger
        key={company.id}
        companyId={company.id}
        canCancel
        canReprint={canReprint}
        onReprint={canReprint ? onReprint : undefined}
      />
      <ColisSalesJournalPanel key={`${company.id}-journal`} companyId={company.id} companyName={company.name} />
    </div>
  );
}

export default function CompanySalesPage() {
  const { selectedCompany, isLoading, isReady } = useOwnerCompany();

  if (!isReady || isLoading) {
    return <Skeleton className="h-48 w-full" />;
  }

  if (!selectedCompany) {
    return <p className="text-sm text-muted-foreground p-6">Compagnie introuvable.</p>;
  }

  return <CompanySalesPageContent company={selectedCompany} />;
}
