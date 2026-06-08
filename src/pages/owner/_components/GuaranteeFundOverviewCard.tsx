import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowRightIcon, LandmarkIcon } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
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
    return <Skeleton className="h-28 w-full rounded-xl" />;
  }

  const balanceLabel =
    fund != null
      ? `${fund.balance.toLocaleString()} ${fund.currency}`
      : t("console.guarantee_balance_unavailable", { defaultValue: "Solde à consulter" });

  return (
    <Link
      to={`/${lng ?? "fr"}/owner/guarantee-fund`}
      className="block h-full"
      data-tour="owner-guarantee-fund"
    >
      <Card className="h-full hover:border-primary/40 hover:shadow-md transition-all group">
        <CardContent className="p-4 flex flex-col gap-3 h-full">
          <div className="flex items-start justify-between gap-3">
            <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
              <LandmarkIcon className="w-5 h-5 text-primary" />
            </div>
            {fund != null && fund.pendingDeposits > 0 && (
              <Badge variant="secondary" className="text-[10px] shrink-0">
                {fund.pendingDeposits}{" "}
                {t("console.guarantee_pending", { defaultValue: "dépôt(s) en attente" })}
              </Badge>
            )}
          </div>
          <div className="space-y-1 flex-1">
            <h3 className="font-semibold text-sm leading-snug">
              {t("console.guarantee_title", { defaultValue: "Fond de garantie" })}
            </h3>
            <p
              className={`text-xl font-black tracking-tight ${
                fund != null && fund.balance < 0 ? "text-destructive" : "text-foreground"
              }`}
            >
              {balanceLabel}
            </p>
            <p className="text-xs text-muted-foreground leading-relaxed">
              {t("console.guarantee_desc", {
                defaultValue: "Solde, dépôts plateforme et validation comptable.",
              })}
            </p>
          </div>
          <span className="text-xs font-medium text-primary inline-flex items-center gap-1 group-hover:gap-2 transition-all">
            {t("console.open", { defaultValue: "Ouvrir" })}
            <ArrowRightIcon className="w-3.5 h-3.5" />
          </span>
        </CardContent>
      </Card>
    </Link>
  );
}
