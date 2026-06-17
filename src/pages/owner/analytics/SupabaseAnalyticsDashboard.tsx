import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, useParams } from "react-router-dom";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  ArrowDownRightIcon,
  ArrowUpRightIcon,
  BusIcon,
  CalendarIcon,
  ReceiptTextIcon,
  TicketIcon,
  TrendingUpIcon,
  UserCheckIcon,
  UsersIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import ConsoleGridTile from "@/components/console/ConsoleGridTile.tsx";
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getCompanyAccountingDashboardSupabase,
  type CompanyAccountingDashboard,
  type CompanyRecentBooking,
} from "@/lib/supabase/accounting";
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";

function statusVariant(status: string) {
  switch (status) {
    case "confirmed":
    case "collected":
      return "default" as const;
    case "pending_payment":
      return "secondary" as const;
    case "cancelled":
      return "destructive" as const;
    default:
      return "secondary" as const;
  }
}

function RevenueChart({ dashboard }: { dashboard: CompanyAccountingDashboard }) {
  const { t } = useTranslation("analytics");
  const formatted = dashboard.revenueChart.map((point) => ({
    ...point,
    label: new Date(`${point.date}T00:00:00`).toLocaleDateString(undefined, {
      day: "numeric",
      month: "short",
    }),
  }));

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">{t("chart.revenue_title")}</CardTitle>
        <p className="text-xs text-muted-foreground">{t("chart.last_30_days")}</p>
      </CardHeader>
      <CardContent>
        <div className="h-64 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={formatted} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="supabaseRevenueGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
              <XAxis dataKey="label" tick={{ fontSize: 11 }} interval="preserveStartEnd" />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip
                contentStyle={{
                  borderRadius: "8px",
                  border: "1px solid hsl(var(--border))",
                  background: "hsl(var(--card))",
                  fontSize: "12px",
                }}
                formatter={(value: number) => [value.toLocaleString(), t("chart.revenue")]}
              />
              <Area
                type="monotone"
                dataKey="revenue"
                stroke="hsl(var(--primary))"
                strokeWidth={2}
                fillOpacity={1}
                fill="url(#supabaseRevenueGradient)"
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </CardContent>
    </Card>
  );
}

function RecentBookingsTable({ bookings }: { bookings: CompanyRecentBooking[] }) {
  const { t } = useTranslation("analytics");

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">{t("recent.title")}</CardTitle>
        <p className="text-xs text-muted-foreground">{t("recent.desc")}</p>
      </CardHeader>
      <CardContent>
        {bookings.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <TicketIcon />
              </EmptyMedia>
              <EmptyTitle>{t("recent.empty")}</EmptyTitle>
              <EmptyDescription>
                {t("recent.empty_desc", {
                  defaultValue: "Bookings will appear here once customers start booking.",
                })}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left">
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.passenger")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.route")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.bus")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.seller")}</th>
                  <th className="pb-2 pr-3 font-medium text-muted-foreground text-xs">{t("recent.amount")}</th>
                  <th className="pb-2 font-medium text-muted-foreground text-xs">{t("recent.status")}</th>
                </tr>
              </thead>
              <tbody>
                {bookings.map((booking) => (
                  <tr key={booking._id} className="border-b last:border-0 hover:bg-muted/30">
                    <td className="py-2.5 pr-3">
                      <div className="font-medium">{booking.passengerName}</div>
                      <div className="text-xs text-muted-foreground">{booking.bookingReference}</div>
                    </td>
                    <td className="py-2.5 pr-3 text-xs">
                      {booking.originCity} → {booking.destinationCity}
                    </td>
                    <td className="py-2.5 pr-3 text-xs">{booking.busName}</td>
                    <td className="py-2.5 pr-3 text-xs">{booking.sellerName ?? "—"}</td>
                    <td className="py-2.5 pr-3 font-medium">
                      {booking.totalPrice.toLocaleString()} {booking.currency}
                    </td>
                    <td className="py-2.5">
                      <Badge variant={statusVariant(booking.status)} className="text-[10px]">
                        {booking.status}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export default function SupabaseAnalyticsDashboard() {
  const { t } = useTranslation("analytics");
  const { lng } = useParams<{ lng: string }>();
  const { companyId, isReady, isLoading: companyLoading } = useOwnerCompany();
  const [dashboard, setDashboard] = useState<CompanyAccountingDashboard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!isReady) return;

    if (!companyId) {
      setDashboard(null);
      setError(null);
      setLoading(false);
      return;
    }

    let cancelled = false;

    void (async () => {
      try {
        setLoading(true);
        const data = await getCompanyAccountingDashboardSupabase(companyId);
        if (!cancelled) {
          setDashboard(data);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) {
          setDashboard(null);
          setError(err instanceof Error ? err.message : "Erreur de chargement");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [companyId, isReady]);

  useEffect(() => {
    if (!companyId) return;
    const onRefresh = () => {
      setLoading(true);
      void getCompanyAccountingDashboardSupabase(companyId)
        .then((data) => {
          setDashboard(data);
          setError(null);
        })
        .catch((err) => {
          setDashboard(null);
          setError(err instanceof Error ? err.message : "Erreur de chargement");
        })
        .finally(() => setLoading(false));
    };
    window.addEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
  }, [companyId, isReady]);

  if (loading) {
    return (
      <div className="p-6 space-y-6">
        <Skeleton className="h-8 w-64" />
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <Skeleton key={i} className="h-28 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-64 rounded-xl" />
      </div>
    );
  }

  if (error || !dashboard) {
    return (
      <div className="max-w-lg mx-auto px-4 py-12 text-center space-y-3">
        <p className="text-destructive text-sm">{error ?? "Données indisponibles"}</p>
        <Button variant="secondary" onClick={() => window.location.reload()}>
          {t("buttons.retry", { ns: "common", defaultValue: "Réessayer" })}
        </Button>
      </div>
    );
  }

  const kpis = dashboard.kpis;
  const kpiCards = [
    { label: t("kpi.total_tickets"), value: String(kpis.totalBookings), icon: TicketIcon },
    { label: t("kpi.confirmed"), value: String(kpis.confirmedBookings), icon: UserCheckIcon },
    {
      label: t("kpi.total_revenue"),
      value: `${kpis.totalRevenue.toLocaleString()} ${kpis.currency}`,
      icon: TrendingUpIcon,
    },
    {
      label: t("kpi.today_revenue"),
      value: `${kpis.todayRevenue.toLocaleString()} ${kpis.currency}`,
      icon: ArrowUpRightIcon,
    },
    {
      label: "Caisse",
      value: `${kpis.caisseRevenue.toLocaleString()} ${kpis.currency}`,
      icon: ReceiptTextIcon,
    },
    {
      label: "Commissions",
      value: `${kpis.sellerCommissionsPending.toLocaleString()} ${kpis.currency}`,
      icon: ArrowDownRightIcon,
    },
    { label: t("kpi.upcoming_trips"), value: String(kpis.upcomingTrips), icon: CalendarIcon },
    { label: t("kpi.active_buses"), value: String(kpis.totalBuses), icon: BusIcon },
    { label: t("kpi.travelers"), value: String(kpis.totalTravelers), icon: UsersIcon },
  ];

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("title")}</h1>
          <p className="text-muted-foreground text-sm mt-1">{t("desc")}</p>
        </div>
        <div className="flex gap-2">
          <Button variant="secondary" size="sm" className="cursor-pointer" asChild>
            <Link to={`/${lng}/owner/analytics/tickets`}>{t("nav.tickets")}</Link>
          </Button>
          <Button variant="secondary" size="sm" className="cursor-pointer" asChild>
            <Link to={`/${lng}/owner/analytics/trips`}>{t("nav.trips")}</Link>
          </Button>
          <Button variant="secondary" size="sm" className="cursor-pointer" asChild>
            <Link to={`/${lng}/owner/analytics/travelers`}>{t("nav.travelers")}</Link>
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        {kpiCards.map(({ label, value, icon }, i) => (
          <ConsoleGridTile key={label} tileIndex={i} icon={icon} label={label} value={value} />
        ))}
      </div>

      <RevenueChart dashboard={dashboard} />
      <RecentBookingsTable bookings={dashboard.recentBookings} />
    </div>
  );
}
