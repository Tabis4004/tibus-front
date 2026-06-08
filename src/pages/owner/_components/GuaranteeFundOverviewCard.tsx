import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowRightIcon, LandmarkIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getCompanyGuaranteeFundSupabase,
  type CompanyGuaranteeFund,
} from "@/lib/supabase/guarantee-fund.ts";

export default function GuaranteeFundOverviewCard({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const [fund, setFund] = useState<CompanyGuaranteeFund | null | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    setFund(undefined);
    void getCompanyGuaranteeFundSupabase(companyId)
      .then((row) => {
        if (!cancelled) setFund(row);
      })
      .catch(() => {
        if (!cancelled) setFund(null);
      });
    return () => {
      cancelled = true;
    };
  }, [companyId]);

  if (fund === undefined) {
    return <Skeleton className="h-[4.5rem] w-full rounded-xl" />;
  }

  const balanceLabel =
    fund != null
      ? `${fund.balance.toLocaleString()} ${fund.currency}`
      : t("console.guarantee_balance_unavailable", { defaultValue: "Solde à consulter" });

  return (
    <Link
      to={`/${lng ?? "fr"}/owner/guarantee-fund`}
      className="block"
      data-tour="owner-guarantee-fund"
    >
      <div className="rounded-xl border bg-card p-4 flex items-center gap-4 hover:border-primary/40 hover:shadow-sm transition-all group">
        <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
          <LandmarkIcon className="w-5 h-5 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h3 className="font-semibold text-sm">
              {t("console.guarantee_title", { defaultValue: "Fond de garantie" })}
            </h3>
            {fund != null && fund.pendingDeposits > 0 && (
              <Badge variant="secondary" className="text-[10px]">
                {fund.pendingDeposits}{" "}
                {t("console.guarantee_pending", { defaultValue: "dépôt(s) en attente" })}
              </Badge>
            )}
          </div>
          <p
            className={`text-sm font-bold mt-0.5 ${
              fund != null && fund.balance < 0 ? "text-destructive" : "text-primary"
            }`}
          >
            {balanceLabel}
          </p>
          <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">
            {t("console.guarantee_desc", {
              defaultValue: "Solde, dépôts plateforme et validation comptable.",
            })}
          </p>
        </div>
        <ArrowRightIcon className="w-4 h-4 text-muted-foreground group-hover:text-primary shrink-0 transition-colors" />
      </div>
    </Link>
  );
}
