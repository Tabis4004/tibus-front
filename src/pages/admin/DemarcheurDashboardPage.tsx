import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon, BuildingIcon, RefreshCwIcon, TrendingUpIcon } from "lucide-react";
import AppHeader from "../layout/_components/AppHeader.tsx";
import BottomNav from "../layout/_components/BottomNav.tsx";
import { toast } from "sonner";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { canAccessDemarcheurDashboard } from "@/lib/auth/demarcheur-access.ts";
import {
  getDemarcheurDashboardSupabase,
  type DemarcheurCompanyRow,
  type DemarcheurDashboard,
} from "@/lib/supabase/demarcheur-dashboard.ts";
import StakeholderPayoutDashboardPanel from "./_components/StakeholderPayoutDashboardPanel.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";

function monthStartIso() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().slice(0, 10);
}

function formatMoney(value: number, currency: string) {
  return `${value.toLocaleString(undefined, { maximumFractionDigits: 0 })} ${currency}`;
}

function CompanyPerformanceRow({ row }: { row: DemarcheurCompanyRow }) {
  return (
    <div className="py-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b last:border-b-0">
      <div className="min-w-0">
        <div className="font-medium truncate flex items-center gap-2">
          <BuildingIcon className="w-4 h-4 text-primary shrink-0" />
          {row.name}
        </div>
        <p className="text-xs text-muted-foreground truncate">
          {row.managerName ?? "—"} · {row.countryName ?? "—"}
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-2 text-xs">
        <Badge variant={row.isActive ? "default" : "secondary"}>
          {row.isActive ? "Active" : "Inactive"}
        </Badge>
        <Badge variant="outline">{row.ticketCount} billet(s)</Badge>
        <Badge variant="secondary">{formatMoney(row.salesTotal, row.currency)}</Badge>
        <Badge variant="outline" className="border-primary/30 text-primary">
          {formatMoney(row.commissionEarned, row.currency)} comm.
        </Badge>
      </div>
    </div>
  );
}

export default function DemarcheurDashboardPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("admin");
  const appUser = useAppUser();
  const canAccess = canAccessDemarcheurDashboard(appUser.roles, appUser.isSuperAdmin);
  const [dateFrom, setDateFrom] = useState(monthStartIso());
  const [dateTo, setDateTo] = useState(new Date().toISOString().slice(0, 10));
  const [dashboard, setDashboard] = useState<DemarcheurDashboard | undefined>(undefined);
  const [loading, setLoading] = useState(false);

  const totals = useMemo(() => {
    const rows = dashboard?.companies ?? [];
    return {
      companies: rows.length,
      tickets: rows.reduce((sum, row) => sum + row.ticketCount, 0),
      sales: rows.reduce((sum, row) => sum + row.salesTotal, 0),
      commissions: rows.reduce((sum, row) => sum + row.commissionEarned, 0),
      currency: rows[0]?.currency ?? "XOF",
    };
  }, [dashboard]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const next = await getDemarcheurDashboardSupabase({
        dateFrom: `${dateFrom}T00:00:00.000Z`,
        dateTo: `${dateTo}T23:59:59.999Z`,
      });
      setDashboard(next);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Chargement impossible");
      setDashboard(undefined);
    } finally {
      setLoading(false);
    }
  }, [dateFrom, dateTo]);

  useEffect(() => {
    if (!appUser.isReady) return;
    if (!canAccess) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
      return;
    }
    void load();
  }, [appUser.isReady, canAccess, load, lng, navigate]);

  if (!appUser.isReady || !canAccess) {
    return (
      <div className="flex flex-col min-h-screen">
        <AppHeader />
        <div className="max-w-5xl mx-auto px-4 py-8 space-y-4 flex-1">
          <Skeleton className="h-10 w-64" />
          <Skeleton className="h-40 w-full" />
        </div>
        <BottomNav />
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-screen">
      <AppHeader />
      <main className="flex-1 pb-20 md:pb-0">
    <div className="max-w-5xl mx-auto px-4 py-8 space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
            <TrendingUpIcon className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h1 className="text-xl font-extrabold">
              {t("demarcheur.title", { defaultValue: "Espace démarcheur" })}
            </h1>
            <p className="text-sm text-muted-foreground">
              {t("demarcheur.subtitle", {
                defaultValue: "Performance des compagnies recrutées et commissions recruteur.",
              })}
            </p>
          </div>
        </div>
        <Button variant="outline" size="sm" asChild>
          <Link to={`/${lng ?? "fr"}`}>
            <ArrowLeftIcon className="w-4 h-4 mr-1" />
            Accueil
          </Link>
        </Button>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">
            {t("demarcheur.period", { defaultValue: "Période" })}
          </CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap items-end gap-3">
          <div className="space-y-1">
            <Label htmlFor="demarcheur-from">Du</Label>
            <Input
              id="demarcheur-from"
              type="date"
              value={dateFrom}
              onChange={(event) => setDateFrom(event.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="demarcheur-to">Au</Label>
            <Input
              id="demarcheur-to"
              type="date"
              value={dateTo}
              onChange={(event) => setDateTo(event.target.value)}
            />
          </div>
          <Button type="button" disabled={loading} onClick={() => void load()}>
            <RefreshCwIcon className="w-4 h-4 mr-1" />
            Actualiser
          </Button>
        </CardContent>
      </Card>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Card>
          <CardContent className="pt-4 text-center">
            <div className="text-2xl font-bold">{totals.companies}</div>
            <div className="text-xs text-muted-foreground">Compagnies</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4 text-center">
            <div className="text-2xl font-bold">{totals.tickets}</div>
            <div className="text-xs text-muted-foreground">Billets</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4 text-center">
            <div className="text-2xl font-bold">{formatMoney(totals.sales, totals.currency)}</div>
            <div className="text-xs text-muted-foreground">Ventes</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4 text-center">
            <div className="text-2xl font-bold text-primary">
              {formatMoney(totals.commissions, totals.currency)}
            </div>
            <div className="text-xs text-muted-foreground">Commissions recruteur</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <BuildingIcon className="w-4 h-4" />
            {t("demarcheur.companies_title", { defaultValue: "Mes compagnies recrutées" })}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading && dashboard === undefined ? (
            <div className="space-y-3">
              <Skeleton className="h-14 w-full" />
              <Skeleton className="h-14 w-full" />
            </div>
          ) : !dashboard || dashboard.companies.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("demarcheur.no_companies", {
                defaultValue: "Aucune compagnie ne vous est attribuée comme recruteur.",
              })}
            </p>
          ) : (
            dashboard.companies.map((row) => (
              <CompanyPerformanceRow key={row.companyId} row={row} />
            ))
          )}
        </CardContent>
      </Card>

      <StakeholderPayoutDashboardPanel
        embedded
        countryId={dashboard?.countryId ?? appUser.profile?.countryId ?? null}
      />
    </div>
      </main>
      <BottomNav />
    </div>
  );
}
