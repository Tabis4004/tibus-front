import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
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
import { motion } from "motion/react";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import {
  getMyCompanySupabase,
  type OwnerCompany,
} from "@/lib/supabase/owner-company";
import {
  getCompanyAccountingDashboardSupabase,
  type CompanyAccountingDashboard,
} from "@/lib/supabase/accounting";
import OwnerConsoleModules, {
  OwnerCompanyBanner,
  OwnerProfileCard,
} from "./_components/OwnerConsoleModules.tsx";
import ConsoleGridTile from "@/components/console/ConsoleGridTile.tsx";
import { resolvePrimaryGareStaffDashboardPath } from "@/lib/gare-role-routing.ts";
import { isGareStaffOnlyConsoleUser } from "@/lib/owner-team-roles.ts";

export default function SupabaseOwnerOverview() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { appUserId } = useSupabaseAuth();
  const appUser = useAppUser();
  const { companyId, isReady, isLoading: companyLoading } = useOwnerCompany();
  const [company, setCompany] = useState<OwnerCompany | null | undefined>(undefined);
  const [dashboard, setDashboard] = useState<CompanyAccountingDashboard | null | undefined>(
    undefined,
  );
  const [error, setError] = useState<string | null>(null);

  const firstName =
    appUser.profile?.firstName ??
    appUser.profile?.email?.split("@")[0] ??
    t("console.default_user", { defaultValue: "Utilisateur Tibus" });

  useEffect(() => {
    if (!appUser.isReady) return;
    if (!isGareStaffOnlyConsoleUser(appUser.roles)) return;
    navigate(resolvePrimaryGareStaffDashboardPath(lng ?? "fr", appUser.roles), { replace: true });
  }, [appUser.isReady, appUser.roles, lng, navigate]);

  useEffect(() => {
    if (!appUserId || !isReady) return;

    if (!companyId) {
      setCompany(null);
      setDashboard(null);
      setError(null);
      return;
    }

    let cancelled = false;
    setCompany(undefined);
    setDashboard(undefined);

    void (async () => {
      try {
        const [companyRow, dashboardRow] = await Promise.all([
          getMyCompanySupabase(appUserId, companyId),
          getCompanyAccountingDashboardSupabase(companyId),
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
  }, [appUserId, companyId, isReady]);

  if (
    !isReady ||
    companyLoading ||
    company === undefined ||
    dashboard === undefined ||
    appUser.isLoading
  ) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-20 w-full rounded-xl" />
        <div className="grid grid-cols-2 gap-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-20 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-48 w-full rounded-xl" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-12 text-center space-y-3">
        <p className="text-destructive text-sm">{error}</p>
        <Button variant="secondary" onClick={() => window.location.reload()}>
          {t("buttons.retry", { ns: "common", defaultValue: "Réessayer" })}
        </Button>
      </div>
    );
  }

  if (!company) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-12 text-center space-y-5">
        <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto">
          <BuildingIcon className="w-8 h-8 text-primary" />
        </div>
        <div>
          <h2 className="text-xl font-bold">{t("overview.no_company")}</h2>
          <p className="text-muted-foreground text-sm mt-1">{t("overview.no_company_desc")}</p>
        </div>
        <Button asChild>
          <Link to={`/${lng}/owner/company${company ? "?new=1" : ""}`}>
            {t("overview.create_company")}
          </Link>
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
    },
    {
      label: t("console.kpi_cash", { defaultValue: "Caisse" }),
      value: formatMoney(kpis?.caisseRevenue),
      icon: ReceiptTextIcon,
    },
    {
      label: t("console.kpi_commissions", { defaultValue: "Commissions" }),
      value: formatMoney(kpis?.sellerCommissionsPending),
      icon: PercentIcon,
    },
    {
      label: t("sidebar.trips"),
      value: String(kpis?.upcomingTrips ?? 0),
      icon: CalendarIcon,
    },
  ];

  return (
    <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.25 }}
      >
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("console.greeting", { name: firstName, defaultValue: `Bonjour, ${firstName}` })}
        </h1>
        <p className="text-muted-foreground text-sm mt-1">
          {t("console.subtitle", {
            defaultValue: "Console opérationnelle de votre compagnie.",
          })}
        </p>
      </motion.div>

      <OwnerCompanyBanner company={company} />

      <div className="space-y-2" data-tour="owner-overview">
        <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider px-1">
          {t("console.kpi_section", { defaultValue: "Indicateurs" })}
        </h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {stats.map(({ label, icon, value }, i) => (
            <motion.div
              key={label}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.04 * i }}
            >
              <ConsoleGridTile tileIndex={i} icon={icon} label={label} value={value} />
            </motion.div>
          ))}
        </div>
      </div>

      <OwnerProfileCard company={company} />
      <OwnerConsoleModules company={company} />
    </div>
  );
}
