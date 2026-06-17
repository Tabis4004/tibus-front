import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { BuildingIcon, ChevronsUpDownIcon, PlusIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { cn } from "@/lib/utils.ts";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";

export default function OwnerCompanySwitcher({
  compact = false,
  sidebarTone = false,
  className,
}: {
  compact?: boolean;
  sidebarTone?: boolean;
  className?: string;
}) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const { companies, selectedCompanyId, setSelectedCompanyId, isLoading } = useOwnerCompany();

  const locale = lng ?? "fr";
  const createFirstPath = `/${locale}/owner/company`;
  const createAnotherPath = `/${locale}/owner/company?new=1`;

  const label = (company: (typeof companies)[number]) =>
    company.countryName
      ? `${company.name} — ${company.countryName}`
      : company.name;

  const accentLink = sidebarTone
    ? "text-orange-700 hover:text-orange-800 dark:text-orange-300"
    : "text-primary";
  const accentIconWrap = sidebarTone ? "bg-orange-400/15" : "bg-primary/10";
  const accentIcon = sidebarTone ? "text-orange-600 dark:text-orange-300" : "text-primary";

  const addCompanyLink = (
    <Link
      to={createAnotherPath}
      className={cn(
        "flex items-center gap-2 text-xs font-medium hover:underline",
        accentLink,
        compact ? "px-0" : "mt-2 px-1",
      )}
    >
      <PlusIcon className="w-3.5 h-3.5 shrink-0" />
      <span className="truncate">
        {t("company.add_company", { defaultValue: "Créer une autre compagnie" })}
      </span>
    </Link>
  );

  if (isLoading) {
    return (
      <div className={cn(compact ? "min-w-0 flex-1" : "px-3 mb-3", className)}>
        <Skeleton className={compact ? "h-10 w-full rounded-lg" : "h-16 w-full rounded-xl"} />
      </div>
    );
  }

  if (companies.length === 0) {
    return (
      <div className={cn(compact ? "min-w-0 flex-1 space-y-2" : "px-3 mb-3", className)}>
        {!compact && (
          <div className="text-[10px] uppercase tracking-wide text-muted-foreground mb-1.5 px-1">
            {t("company.active_label")}
          </div>
        )}
        <div
          className={cn(
            "rounded-xl border border-dashed bg-muted/20",
            compact ? "px-3 py-2" : "px-3 py-3 space-y-3",
          )}
        >
          {!compact && (
            <p className="text-xs text-muted-foreground">
              {t("company.no_company_sidebar", {
                defaultValue: "Aucune compagnie pour le moment.",
              })}
            </p>
          )}
          <Button asChild size={compact ? "sm" : "default"} className={compact ? "w-full" : "w-full"}>
            <Link to={createFirstPath}>
              <PlusIcon className="w-4 h-4 mr-1.5" />
              {t("overview.create_company")}
            </Link>
          </Button>
        </div>
      </div>
    );
  }

  const selectedCompany =
    companies.find((row) => row.id === selectedCompanyId) ?? companies[0];

  return (
    <div className={cn(compact ? "min-w-0 flex-1 space-y-2" : "px-3 mb-3", className)}>
      <div
        className={cn(
          "text-[10px] uppercase tracking-wide text-muted-foreground",
          compact ? "sr-only" : "mb-1.5 px-1",
        )}
      >
        {companies.length > 1
          ? t("company.switch_label")
          : t("company.active_label")}
      </div>
      <Select
        value={selectedCompanyId ?? selectedCompany.id}
        onValueChange={(value) => void setSelectedCompanyId(value)}
      >
        <SelectTrigger
          className={cn(
            "bg-muted/30 border-border w-full",
            compact ? "h-10" : "h-11",
          )}
        >
          <div className="flex items-center gap-2 min-w-0 flex-1 text-left">
            {selectedCompany.logo ? (
              <img
                src={selectedCompany.logo}
                alt=""
                className="w-6 h-6 rounded-md object-cover shrink-0"
              />
            ) : (
              <div
                className={cn(
                  "w-6 h-6 rounded-md flex items-center justify-center shrink-0",
                  accentIconWrap,
                )}
              >
                <BuildingIcon className={cn("w-3.5 h-3.5", accentIcon)} />
              </div>
            )}
            <SelectValue placeholder={t("company.select")} />
          </div>
          <ChevronsUpDownIcon className="w-4 h-4 opacity-50 shrink-0" />
        </SelectTrigger>
        <SelectContent>
          {companies.map((company) => (
            <SelectItem key={company.id} value={company.id}>
              {label(company)}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {addCompanyLink}
    </div>
  );
}
