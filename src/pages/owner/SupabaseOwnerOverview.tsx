import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  BuildingIcon,
  CalendarIcon,
  PercentIcon,
  ReceiptTextIcon,
  TrendingUpIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { cn } from "@/lib/utils.ts";
import { motion } from "motion/react";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  getMyCompanySupabase,
  type OwnerCompany,
} from "@/lib/supabase/owner-company";
import {
  getCompanyAccountingDashboardSupabase,
  type CompanyAccountingDashboard,
} from "@/lib/supabase/accounting";
import OwnerConsoleModules, {
  OwnerProfileCard,
} from "./_components/OwnerConsoleModules.tsx";

export default function SupabaseOwnerOverview() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const [company, setCompany] = useState<OwnerCompany | null | undefined>(
    undefined,
  );
  const [dashboard, setDashboard] = useState<CompanyAccountingDashboard | null | undefined>(
    undefined,
  );
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!appUserId) return;

    let cancelled = false;

    void (async () => {
      try {
        const [companyRow, dashboardRow] = await Promise.all([
          getMyCompanySupabase(appUserId),
          getCompanyAccountingDashboardSupabase(),
        ]);
        if (!cancelled) {
          setCompany(companyRow);
          setDashboard(dashboardRow);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) {
          setCompany(null);
          setDashboard(null);
          setError(err instanceof Error ? err.message : "Erreur de chargement");
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [appUserId]);

  if (company === undefined || dashboard === undefined || appUser.isLoading) {
    return (
      <div className="p-6 space-y-4 max-w-6xl mx-auto">
        <Skeleton className="h-10 w-72" />
        <div className="grid lg:grid-cols-[320px_1fr] gap-6">
          <Skeleton className="h-80 w-full" />
          <Skeleton className="h-80 w-full" />
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="max-w-lg mx-auto px-4 py-12 text-center space-y-3">
        <p className="text-destructive text-sm">{error}</p>
        <Button variant="secondary" onClick={() => window.location.reload()}>
          {t("buttons.retry", { ns: "common", defaultValue: "Réessayer" })}
        </Button>
      </div>
    );
  }

  if (!company) {
    return (
      <div className="max-w-lg mx-auto px-4 py-12 text-center space-y-5">
        <div className="w-16 h-16 rounded-2xl bg-muted flex items-center justify-center mx-auto">
          <BuildingIcon className="w-8 h-8 text-muted-foreground" />
        </div>
        <div>
          <h2 className="text-xl font-bold">{t("overview.no_company")}</h2>
          <p className="text-muted-foreground text-sm mt-1">
            {t("overview.no_company_desc")}
          </p>
        </div>
        <Button asChild>
          <Link to={`/${lng}/owner/company`}>{t("overview.create_company")}</Link>
        </Button>
      </div>
    );
  }

  const kpis = dashboard?.kpis;
  const currency = kpis?.currency ?? company.currency ?? "XOF";
  const formatMoney = (amount: number | undefined) =>
    `${(amount ?? 0).toLocaleString()} ${currency}`;

  const stats = [
    {
      label: t("console.kpi_revenue", { defaultValue: "Revenus" }),
      value: formatMoney(kpis?.totalRevenue),
      icon: TrendingUpIcon,
      color: "text-emerald-500",
    },
    {
      label: t("console.kpi_cash", { defaultValue: "Caisse" }),
      value: formatMoney(kpis?.caisseRevenue),
      icon: ReceiptTextIcon,
      color: "text-amber-500",
    },
    {
      label: t("console.kpi_commissions", { defaultValue: "Commissions" }),
      value: formatMoney(kpis?.sellerCommissionsPending),
      icon: PercentIcon,
      color: "text-rose-500",
    },
    {
      label: t("sidebar.trips"),
      value: String(kpis?.upcomingTrips ?? 0),
      icon: CalendarIcon,
      color: "text-indigo-500",
    },
  ];

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.25 }}
        className="space-y-1"
      >
        <p className="text-xs font-semibold uppercase tracking-wider text-primary">
          Tibus Journey Planner
        </p>
        <h1 className="text-2xl md:text-3xl font-extrabold tracking-tight">
          {t("console.title", { defaultValue: "Console opérationnelle" })}
        </h1>
        <p className="text-sm text-muted-foreground">
          {company.name}
          {company.managerName ? ` · ${company.managerName}` : ""}
        </p>
      </motion.div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {stats.map(({ label, icon: Icon, value, color }, i) => (
          <motion.div
            key={label}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.05 * i }}
            className="rounded-xl border bg-card p-3"
          >
            <div className="flex items-center gap-2 mb-1">
              <Icon className={cn("w-4 h-4", color)} />
              <span className="text-[11px] text-muted-foreground">{label}</span>
            </div>
            <div className="text-lg font-bold truncate">{value}</div>
          </motion.div>
        ))}
      </div>

      <div className="grid lg:grid-cols-[minmax(280px,320px)_1fr] gap-6 items-start">
        <OwnerProfileCard company={company} />
        <OwnerConsoleModules company={company} />
      </div>
    </div>
  );
}
