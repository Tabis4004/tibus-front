import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { format } from "date-fns";
import { BusIcon } from "lucide-react";
import { Card, CardContent, CardHeader } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import {
  getOwnerTripReportSupabase,
  type OwnerTripReport,
} from "@/lib/supabase/owner-reports";

export default function SupabaseTripReports() {
  const { t } = useTranslation("analytics");
  const { appUserId } = useSupabaseAuth();
  const [report, setReport] = useState<OwnerTripReport | undefined>(undefined);
  const [routeFilter, setRouteFilter] = useState("all");

  useEffect(() => {
    if (!appUserId) return;
    let cancelled = false;
    void getOwnerTripReportSupabase(appUserId)
      .then((data) => {
        if (!cancelled) setReport(data);
      })
      .catch(() => {
        if (!cancelled) {
          setReport({
            trips: [],
            filters: { buses: [], routes: [], departureCities: [], departureStations: [] },
          });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [appUserId]);

  const filteredTrips = useMemo(() => {
    const trips = report?.trips ?? [];
    if (routeFilter === "all") return trips;
    return trips.filter((trip) => trip.routeId === routeFilter);
  }, [report, routeFilter]);

  const totalRevenue = filteredTrips.reduce((sum, trip) => sum + trip.revenue, 0);

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("report.trips_title", { defaultValue: "Rapport trajets" })}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          {t("report.trips_desc", { defaultValue: "Performance par départ." })}
        </p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">Départs</p>
            <p className="text-2xl font-bold">{filteredTrips.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">Revenus</p>
            <p className="text-2xl font-bold">{totalRevenue.toLocaleString()}</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <Select value={routeFilter} onValueChange={setRouteFilter}>
            <SelectTrigger className="w-full sm:w-64">
              <SelectValue placeholder="Route" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Toutes les routes</SelectItem>
              {(report?.filters.routes ?? []).map((route) => (
                <SelectItem key={route.routeId} value={route.routeId}>
                  {route.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </CardHeader>
        <CardContent>
          {report === undefined ? (
            <Skeleton className="h-48 w-full" />
          ) : filteredTrips.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <BusIcon />
                </EmptyMedia>
                <EmptyTitle>Aucun trajet</EmptyTitle>
                <EmptyDescription>Planifiez des départs pour voir les rapports.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-2 px-2">Route</th>
                    <th className="pb-2 px-2">Départ</th>
                    <th className="pb-2 px-2">Bus</th>
                    <th className="pb-2 px-2">Résa</th>
                    <th className="pb-2 px-2">Taux</th>
                    <th className="pb-2 px-2">Revenus</th>
                    <th className="pb-2 px-2">Statut</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredTrips.map((trip) => (
                    <tr key={trip._id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="py-2 px-2">
                        {trip.originCity} → {trip.destinationCity}
                      </td>
                      <td className="py-2 px-2 whitespace-nowrap">
                        {format(new Date(trip.departureTime), "dd/MM/yy HH:mm")}
                      </td>
                      <td className="py-2 px-2">{trip.busName}</td>
                      <td className="py-2 px-2">
                        {trip.bookingCount}/{trip.totalSeats}
                      </td>
                      <td className="py-2 px-2">{trip.occupancyRate}%</td>
                      <td className="py-2 px-2 font-medium">
                        {trip.revenue.toLocaleString()} {trip.currency}
                      </td>
                      <td className="py-2 px-2">
                        <Badge variant="secondary" className="text-[10px] capitalize">
                          {trip.status}
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
    </div>
  );
}
