import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ReceiptIcon } from "lucide-react";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import IncomeStatementPanel from "./_components/IncomeStatementPanel.tsx";

export default function IncomeStatementPage() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const locale = lng ?? "fr";
  const { selectedCompany, isLoading, isReady } = useOwnerCompany();

  if (!isReady || isLoading) {
    return (
      <div className="p-4 md:p-6 max-w-6xl mx-auto space-y-4">
        <Skeleton className="h-8 w-72" />
        <Skeleton className="h-96 w-full rounded-xl" />
      </div>
    );
  }

  if (!selectedCompany) {
    return <p className="p-6 text-sm text-muted-foreground">Compagnie introuvable.</p>;
  }

  return (
    <div className="p-4 md:p-6 max-w-6xl mx-auto space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight text-[#1A5296]">
            {t("income_statement.page_title")}
          </h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            {t("income_statement.page_desc")}
          </p>
        </div>
        <Button variant="outline" size="sm" className="shrink-0" asChild>
          <Link to={`/${locale}/owner/expenses`}>
            <ReceiptIcon className="w-4 h-4 mr-1.5" />
            {t("income_statement.manage_expenses")}
          </Link>
        </Button>
      </div>
      <IncomeStatementPanel key={selectedCompany.id} companyId={selectedCompany.id} />
    </div>
  );
}
