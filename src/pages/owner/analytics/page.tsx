import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { Link, useParams } from "react-router-dom";
import {
  TicketIcon,
  TrendingUpIcon,
  CalendarIcon,
  UsersIcon,
  BusIcon,
  UserCheckIcon,
  ArrowUpRightIcon,
  ArrowDownRightIcon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { cn } from "@/lib/utils.ts";
import RevenueChart from "./_components/RevenueChart.tsx";
import RecentBookingsTable from "./_components/RecentBookingsTable.tsx";

export default function AnalyticsDashboard() {
  const { t } = useTranslation("analytics");
  const { lng } = useParams<{ lng: string }>();
  const kpis = useQuery(api.analytics.getKPIs, {});

  if (kpis === undefined) {
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

  const kpiCards = [
    {
      label: t("kpi.total_tickets"),
      value: kpis.totalBookings,
      icon: TicketIcon,
      color: "text-blue-600",
      bgColor: "bg-blue-50 dark:bg-blue-950/30",
    },
    {
      label: t("kpi.confirmed"),
      value: kpis.confirmedBookings,
      icon: UserCheckIcon,
      color: "text-green-600",
      bgColor: "bg-green-50 dark:bg-green-950/30",
    },
    {
      label: t("kpi.total_revenue"),
      value: `${kpis.totalRevenue.toLocaleString()} ${kpis.currency}`,
      icon: TrendingUpIcon,
      color: "text-emerald-600",
      bgColor: "bg-emerald-50 dark:bg-emerald-950/30",
    },
    {
      label: t("kpi.today_revenue"),
      value: `${kpis.todayRevenue.toLocaleString()} ${kpis.currency}`,
      icon: ArrowUpRightIcon,
      color: "text-orange-600",
      bgColor: "bg-orange-50 dark:bg-orange-950/30",
    },
    {
      label: t("kpi.upcoming_trips"),
      value: kpis.upcomingTrips,
      icon: CalendarIcon,
      color: "text-purple-600",
      bgColor: "bg-purple-50 dark:bg-purple-950/30",
    },
    {
      label: t("kpi.today_trips"),
      value: kpis.todayTrips,
      icon: ArrowDownRightIcon,
      color: "text-indigo-600",
      bgColor: "bg-indigo-50 dark:bg-indigo-950/30",
    },
    {
      label: t("kpi.travelers"),
      value: kpis.totalTravelers,
      icon: UsersIcon,
      color: "text-cyan-600",
      bgColor: "bg-cyan-50 dark:bg-cyan-950/30",
    },
    {
      label: t("kpi.active_buses"),
      value: kpis.totalBuses,
      icon: BusIcon,
      color: "text-rose-600",
      bgColor: "bg-rose-50 dark:bg-rose-950/30",
    },
  ];

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-6">
      {/* Header */}
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

      {/* KPI Grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
        {kpiCards.map(({ label, value, icon: Icon, color, bgColor }) => (
          <Card key={label} className="p-4 relative overflow-hidden">
            <div className={cn("absolute top-3 right-3 w-8 h-8 rounded-lg flex items-center justify-center", bgColor)}>
              <Icon className={cn("w-4 h-4", color)} />
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground font-medium">{label}</p>
              <p className="text-xl font-bold tracking-tight">{value}</p>
            </div>
          </Card>
        ))}
      </div>

      {/* Revenue Chart */}
      <RevenueChart />

      {/* Recent Bookings */}
      <RecentBookingsTable />
    </div>
  );
}
