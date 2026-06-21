import { useTranslation } from "react-i18next";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import CounterCommissionTiersPanel from "./_components/CounterCommissionTiersPanel.tsx";

export default function CounterCommissionsPage() {
  const { t } = useTranslation("owner");
  const { companyId } = useOwnerCompany();

  if (!companyId) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 text-sm text-muted-foreground">
        {t("labels.no_company", { ns: "common", defaultValue: "Aucune compagnie sélectionnée." })}
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">{t("gare.commission_page_title")}</h1>
        <p className="text-muted-foreground text-sm mt-0.5">{t("gare.commission_page_desc")}</p>
      </div>
      <CounterCommissionTiersPanel companyId={companyId} />
    </div>
  );
}
