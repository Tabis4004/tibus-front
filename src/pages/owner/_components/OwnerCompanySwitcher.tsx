import { useTranslation } from "react-i18next";
import { BuildingIcon, ChevronsUpDownIcon } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";

export default function OwnerCompanySwitcher({ compact = false }: { compact?: boolean }) {
  const { t } = useTranslation("owner");
  const { companies, selectedCompanyId, setSelectedCompanyId, isLoading } = useOwnerCompany();

  if (isLoading || companies.length === 0) return null;

  const label = (company: (typeof companies)[number]) =>
    company.countryName
      ? `${company.name} — ${company.countryName}`
      : company.name;

  if (companies.length === 1) {
    const company = companies[0];
    return (
      <div className="px-3 mb-3">
        <div className="rounded-xl border bg-muted/30 px-3 py-2.5">
          <div className="text-[10px] uppercase tracking-wide text-muted-foreground mb-1">
            {t("company.active_label", { defaultValue: "Compagnie active" })}
          </div>
          <div className="flex items-center gap-2 min-w-0">
            {company.logo ? (
              <img src={company.logo} alt="" className="w-8 h-8 rounded-lg object-cover shrink-0" />
            ) : (
              <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                <BuildingIcon className="w-4 h-4 text-primary" />
              </div>
            )}
            <div className="min-w-0">
              <div className="text-sm font-semibold truncate">{company.name}</div>
              {company.countryName && (
                <div className="text-[11px] text-muted-foreground truncate">
                  {company.countryName}
                  {company.currency ? ` · ${company.currency}` : ""}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="px-3 mb-3">
      <div className="text-[10px] uppercase tracking-wide text-muted-foreground mb-1.5 px-1">
        {t("company.switch_label", { defaultValue: "Compagnie active" })}
      </div>
      <Select
        value={selectedCompanyId ?? undefined}
        onValueChange={(value) => void setSelectedCompanyId(value)}
      >
        <SelectTrigger
          className={
            compact
              ? "h-10 bg-muted/30 border-border"
              : "h-11 bg-muted/30 border-border"
          }
        >
          <SelectValue placeholder={t("company.select", { defaultValue: "Choisir une compagnie" })} />
          <ChevronsUpDownIcon className="w-4 h-4 opacity-50" />
        </SelectTrigger>
        <SelectContent>
          {companies.map((company) => (
            <SelectItem key={company.id} value={company.id}>
              {label(company)}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
