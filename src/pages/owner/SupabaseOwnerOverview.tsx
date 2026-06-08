import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  BuildingIcon,
  CalendarIcon,
  ArrowRightIcon,
  PercentIcon,
  BarChart3Icon,
  ReceiptTextIcon,
  TicketIcon,
  TrendingUpIcon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
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
      <div className="p-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-28 w-full" />
        <div className="grid grid-cols-2 gap-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-24 rounded-xl" />
          ))}
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

  const displayName = appUser.profile
    ? `${appUser.profile.firstName} ${appUser.profile.lastName}`.trim()
    : null;
  const kpis = dashboard?.kpis;
  const commissionRate = dashboard?.company.commissionRate ?? company.commissionRate;
  const currency = kpis?.currency ?? company.currency ?? "XOF";
  const formatMoney = (amount: number | undefined) =>
    `${(amount ?? 0).toLocaleString()} ${currency}`;

  const stats = [
    {
      label: "Revenus",
      icon: TrendingUpIcon,
      value: formatMoney(kpis?.totalRevenue),
      toSuffix: "/owner/analytics",
      color: "text-emerald-500",
    },
    {
      label: "Caisse",
      icon: ReceiptTextIcon,
      value: formatMoney(kpis?.caisseRevenue),
      toSuffix: "/owner/analytics",
      color: "text-amber-500",
    },
    {
      label: "Commissions",
      icon: PercentIcon,
      value: formatMoney(kpis?.sellerCommissionsPending),
      toSuffix: "/owner/analytics",
      color: "text-rose-500",
    },
    {
      label: t("sidebar.trips"),
      icon: CalendarIcon,
      value: kpis?.upcomingTrips ?? "—",
      toSuffix: "/owner/trips",
      color: "text-indigo-500",
    },
  ];

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3, ease: "easeOut" }}
      >
        <h1 className="text-2xl font-extrabold tracking-tight">
          {displayName
            ? `Hey, ${displayName.split(" ")[0]}`
            : t("overview.title")}
        </h1>
        <p className="text-muted-foreground text-sm mt-1">{t("overview.desc")}</p>
      </motion.div>

      <Card className="pt-0 overflow-hidden">
        <div className="h-24 bg-gradient-to-br from-primary/20 to-primary/5" />
        <CardContent className="pt-0 -mt-8 pb-5">
          <div className="flex items-end gap-4">
            <div className="w-16 h-16 rounded-2xl border-4 border-background bg-primary/10 flex items-center justify-center shrink-0 overflow-hidden">
              {company.logo ? (
                <img
                  src={company.logo}
                  alt="logo"
                  className="w-full h-full object-cover"
                />
              ) : (
                <BuildingIcon className="w-7 h-7 text-primary" />
              )}
            </div>
            <div className="pb-1 flex-1 min-w-0">
              <h2 className="font-bold text-lg leading-tight truncate">
                {company.name}
              </h2>
              {company.managerName && (
                <p className="text-xs text-muted-foreground line-clamp-1">
                  {company.managerName}
                </p>
              )}
            </div>
            <Button
              size="sm"
              variant="secondary"
              asChild
              className="shrink-0 cursor-pointer"
            >
              <Link to={`/${lng}/owner/company`}>
                {t("buttons.edit", { ns: "common" })}
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {stats.map(({ label, icon: Icon, value, toSuffix, color }, i) => (
          <motion.div
            key={label}
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3, delay: 0.1 + i * 0.05, ease: "easeOut" }}
          >
            <Link to={`/${lng}${toSuffix}`}>
              <Card className="p-4 hover:border-primary/40 hover:shadow-md transition-all cursor-pointer group">
                <div className="w-9 h-9 rounded-lg bg-muted flex items-center justify-center mb-2 group-hover:bg-primary/10 transition-colors">
                  <Icon className={cn("w-4.5 h-4.5", color)} />
                </div>
                <div className="text-2xl font-bold">{value}</div>
                <div className="text-xs text-muted-foreground">{label}</div>
                <ArrowRightIcon className="w-3 h-3 text-muted-foreground mt-2 group-hover:text-primary group-hover:translate-x-0.5 transition-all" />
              </Card>
            </Link>
          </motion.div>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <BarChart3Icon className="w-4 h-4" /> Résumé comptable
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div className="rounded-lg bg-muted p-4">
                <div className="text-xs text-muted-foreground mb-1">Billets confirmés</div>
                <div className="font-bold text-lg">{kpis?.confirmedBookings ?? 0}</div>
              </div>
              <div className="rounded-lg bg-muted p-4">
                <div className="text-xs text-muted-foreground mb-1">Paiement en ligne</div>
                <div className="font-bold text-lg">{formatMoney(kpis?.onlineRevenue)}</div>
              </div>
              <div className="rounded-lg bg-muted p-4">
                <div className="text-xs text-muted-foreground mb-1">Voyageurs</div>
                <div className="font-bold text-lg">{kpis?.totalTravelers ?? 0}</div>
              </div>
              <div className="rounded-lg bg-muted p-4">
                <div className="text-xs text-muted-foreground mb-1">Bus actifs</div>
                <div className="font-bold text-lg">{kpis?.totalBuses ?? 0}</div>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <PercentIcon className="w-4 h-4" /> Commissions
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="rounded-lg bg-muted p-4">
              <div className="text-xs text-muted-foreground mb-1">À payer aux vendeurs</div>
              <div className="font-bold text-lg">{formatMoney(kpis?.sellerCommissionsPending)}</div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-lg border p-3 text-center">
                <TicketIcon className="w-4 h-4 mx-auto mb-1 text-primary" />
                <div className="text-xs text-muted-foreground">Ventes</div>
                <div className="font-bold">{kpis?.totalBookings ?? 0}</div>
              </div>
              <div className="rounded-lg border p-3 text-center">
                <PercentIcon className="w-4 h-4 mx-auto mb-1 text-primary" />
                <div className="text-xs text-muted-foreground">Taux</div>
                <div className="font-bold">{commissionRate}%</div>
              </div>
            </div>
            <Badge variant="secondary" className="text-[10px]">
              {currency}
            </Badge>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
