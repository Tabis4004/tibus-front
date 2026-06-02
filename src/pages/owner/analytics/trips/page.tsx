import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { useState, useMemo, useCallback } from "react";
import { useParams } from "react-router-dom";
import { format } from "date-fns";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import {
  DownloadIcon,
  FilterIcon,
  XIcon,
  SearchIcon,
  CalendarIcon,
  TrendingUpIcon,
  PercentIcon,
  FileSpreadsheetIcon,
  FileTextIcon,
  BusIcon,
} from "lucide-react";
import { Card } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
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
import { cn } from "@/lib/utils.ts";

type TripRow = {
  _id: string;
  _creationTime: number;
  departureTime: string;
  arrivalTime: string;
  status: string;
  priceAmount: number;
  currency: string;
  totalSeats: number;
  seatsAvailable: number;
  busId: string;
  busName: string;
  busPlateNumber: string;
  routeId: string;
  originCity: string;
  destinationCity: string;
  bookingCount: number;
  revenue: number;
  occupancyRate: number;
};

function statusVariant(status: string) {
  switch (status) {
    case "completed":
      return "default" as const;
    case "scheduled":
      return "secondary" as const;
    case "active":
      return "default" as const;
    case "cancelled":
      return "destructive" as const;
    default:
      return "secondary" as const;
  }
}

function exportCSV(trips: TripRow[], t: (key: string) => string) {
  const headers = [
    t("trips.col_route"),
    t("trips.col_bus"),
    t("trips.col_departure"),
    t("trips.col_arrival"),
    t("trips.col_status"),
    t("trips.col_seats"),
    t("trips.col_bookings"),
    t("trips.col_occupancy"),
    t("trips.col_revenue"),
    t("trips.col_currency"),
  ];

  const rows = trips.map((trip) => [
    `${trip.originCity} - ${trip.destinationCity}`,
    `${trip.busName} (${trip.busPlateNumber})`,
    format(new Date(trip.departureTime), "dd/MM/yyyy HH:mm"),
    format(new Date(trip.arrivalTime), "dd/MM/yyyy HH:mm"),
    trip.status,
    String(trip.totalSeats),
    String(trip.bookingCount),
    `${trip.occupancyRate}%`,
    String(trip.revenue),
    trip.currency,
  ]);

  const csvContent = [headers, ...rows]
    .map((row) => row.map((cell) => `"${cell.replace(/"/g, '""')}"`).join(","))
    .join("\n");

  const blob = new Blob(["\uFEFF" + csvContent], { type: "text/csv;charset=utf-8;" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `rapport-voyages-${format(new Date(), "yyyy-MM-dd")}.csv`;
  link.click();
  URL.revokeObjectURL(link.href);
}

function exportPDFReport(trips: TripRow[], companyName: string) {
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });

  doc.setFillColor(75, 0, 130);
  doc.rect(0, 0, 297, 20, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  doc.text(`${companyName} — Rapport des Voyages`, 14, 13);
  doc.setFontSize(8);
  doc.setFont("helvetica", "normal");
  doc.text(`Genere le ${format(new Date(), "dd/MM/yyyy HH:mm")} | ${trips.length} voyages`, 14, 18);

  const head = [["Trajet", "Bus", "Depart", "Statut", "Places", "Reserv.", "Occ.%", "Revenu"]];
  const body = trips.map((trip) => [
    `${trip.originCity} → ${trip.destinationCity}`,
    trip.busName,
    format(new Date(trip.departureTime), "dd/MM/yy HH:mm"),
    trip.status,
    String(trip.totalSeats),
    String(trip.bookingCount),
    `${trip.occupancyRate}%`,
    `${trip.revenue.toLocaleString()} ${trip.currency}`,
  ]);

  autoTable(doc, {
    startY: 24,
    head,
    body,
    theme: "striped",
    styles: { fontSize: 7, cellPadding: 1.5 },
    headStyles: { fillColor: [75, 0, 130], fontSize: 7, fontStyle: "bold" },
    alternateRowStyles: { fillColor: [248, 248, 252] },
  });

  const totalRevenue = trips.reduce((sum, trip) => sum + trip.revenue, 0);
  const currency = trips[0]?.currency ?? "XAF";
  const finalY = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 8;
  doc.setTextColor(0, 0, 0);
  doc.setFontSize(10);
  doc.setFont("helvetica", "bold");
  doc.text(`Revenu Total: ${totalRevenue.toLocaleString()} ${currency}`, 14, finalY);
  doc.setFontSize(7);
  doc.setFont("helvetica", "normal");
  doc.text("Powered By Tibus", 14, finalY + 5);

  doc.save(`rapport-voyages-${format(new Date(), "yyyy-MM-dd")}.pdf`);
}

export default function TripReportsPage() {
  const { t } = useTranslation("analytics");
  const reportData = useQuery(api.analytics.getTripReport, {});
  const company = useQuery(api.companies.getMyCompany, {});

  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [busFilter, setBusFilter] = useState("all");
  const [routeFilter, setRouteFilter] = useState("all");
  const [cityFilter, setCityFilter] = useState("all");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [showFilters, setShowFilters] = useState(false);

  const filteredTrips = useMemo(() => {
    if (!reportData) return [];
    let trips = reportData.trips;

    if (search.trim()) {
      const q = search.toLowerCase();
      trips = trips.filter(
        (trip) =>
          trip.originCity.toLowerCase().includes(q) ||
          trip.destinationCity.toLowerCase().includes(q) ||
          trip.busName.toLowerCase().includes(q) ||
          trip.busPlateNumber.toLowerCase().includes(q)
      );
    }

    if (statusFilter !== "all") {
      trips = trips.filter((trip) => trip.status === statusFilter);
    }
    if (busFilter !== "all") {
      trips = trips.filter((trip) => trip.busId === busFilter);
    }
    if (routeFilter !== "all") {
      trips = trips.filter((trip) => trip.routeId === routeFilter);
    }
    if (cityFilter !== "all") {
      trips = trips.filter((trip) => trip.originCity === cityFilter);
    }

    if (dateFrom) {
      const from = new Date(dateFrom);
      from.setHours(0, 0, 0, 0);
      trips = trips.filter((trip) => new Date(trip.departureTime) >= from);
    }
    if (dateTo) {
      const to = new Date(dateTo);
      to.setHours(23, 59, 59, 999);
      trips = trips.filter((trip) => new Date(trip.departureTime) <= to);
    }

    return trips;
  }, [reportData, search, statusFilter, busFilter, routeFilter, cityFilter, dateFrom, dateTo]);

  const summary = useMemo(() => {
    const total = filteredTrips.length;
    const revenue = filteredTrips.reduce((sum, trip) => sum + trip.revenue, 0);
    const avgOccupancy = total > 0
      ? Math.round(filteredTrips.reduce((sum, trip) => sum + trip.occupancyRate, 0) / total)
      : 0;
    const currency = filteredTrips[0]?.currency ?? "XAF";
    return { total, revenue, avgOccupancy, currency };
  }, [filteredTrips]);

  const activeFilters = useMemo(() => {
    let count = 0;
    if (statusFilter !== "all") count++;
    if (busFilter !== "all") count++;
    if (routeFilter !== "all") count++;
    if (cityFilter !== "all") count++;
    if (dateFrom) count++;
    if (dateTo) count++;
    return count;
  }, [statusFilter, busFilter, routeFilter, cityFilter, dateFrom, dateTo]);

  const clearFilters = useCallback(() => {
    setSearch("");
    setStatusFilter("all");
    setBusFilter("all");
    setRouteFilter("all");
    setCityFilter("all");
    setDateFrom("");
    setDateTo("");
  }, []);

  if (reportData === undefined) {
    return (
      <div className="p-4 md:p-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-20 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-12 w-full rounded-xl" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl font-extrabold tracking-tight">{t("trips.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("trips.desc")}</p>
        </div>
        <div className="flex gap-2">
          <Button
            size="sm"
            variant="secondary"
            onClick={() => exportCSV(filteredTrips, t)}
            disabled={filteredTrips.length === 0}
            className="cursor-pointer shrink-0 text-xs"
          >
            <FileSpreadsheetIcon className="w-3.5 h-3.5 mr-1.5" />
            CSV
          </Button>
          <Button
            size="sm"
            onClick={() => exportPDFReport(filteredTrips, company?.name ?? "Company")}
            disabled={filteredTrips.length === 0}
            className="cursor-pointer shrink-0 text-xs"
          >
            <FileTextIcon className="w-3.5 h-3.5 mr-1.5" />
            PDF
          </Button>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-purple-50 dark:bg-purple-950/30 flex items-center justify-center">
              <CalendarIcon className="w-4 h-4 text-purple-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{t("trips.total_trips")}</p>
              <p className="text-lg font-bold">{summary.total}</p>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-emerald-50 dark:bg-emerald-950/30 flex items-center justify-center">
              <TrendingUpIcon className="w-4 h-4 text-emerald-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{t("trips.total_revenue")}</p>
              <p className="text-lg font-bold">
                {summary.revenue.toLocaleString()} {summary.currency}
              </p>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-blue-50 dark:bg-blue-950/30 flex items-center justify-center">
              <PercentIcon className="w-4 h-4 text-blue-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{t("trips.avg_occupancy")}</p>
              <p className="text-lg font-bold">{summary.avgOccupancy}%</p>
            </div>
          </div>
        </Card>
      </div>

      {/* Search & Filter Toggle */}
      <div className="flex flex-col sm:flex-row gap-2">
        <div className="relative flex-1">
          <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t("trips.search_placeholder")}
            className="pl-9"
          />
        </div>
        <Button
          variant={showFilters ? "secondary" : "ghost"}
          size="sm"
          onClick={() => setShowFilters(!showFilters)}
          className="cursor-pointer shrink-0 gap-1.5"
        >
          <FilterIcon className="w-4 h-4" />
          {t("report.filters")}
          {activeFilters > 0 && (
            <Badge variant="destructive" className="text-[10px] h-4 px-1 ml-1">
              {activeFilters}
            </Badge>
          )}
        </Button>
        {activeFilters > 0 && (
          <Button
            variant="ghost"
            size="sm"
            onClick={clearFilters}
            className="cursor-pointer shrink-0 text-destructive"
          >
            <XIcon className="w-4 h-4 mr-1" />
            {t("report.clear_filters")}
          </Button>
        )}
      </div>

      {/* Filter Panel */}
      {showFilters && (
        <Card className="p-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {/* Status */}
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">
                {t("report.filter_status")}
              </label>
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all")}</SelectItem>
                  <SelectItem value="scheduled">{t("trips.status_scheduled")}</SelectItem>
                  <SelectItem value="active">{t("trips.status_active")}</SelectItem>
                  <SelectItem value="completed">{t("trips.status_completed")}</SelectItem>
                  <SelectItem value="cancelled">{t("trips.status_cancelled")}</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Bus */}
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">
                Bus
              </label>
              <Select value={busFilter} onValueChange={setBusFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all")}</SelectItem>
                  {reportData.filters.buses.map((b) => (
                    <SelectItem key={b._id} value={b._id}>
                      {b.name} ({b.plateNumber})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Route */}
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">
                {t("report.filter_route")}
              </label>
              <Select value={routeFilter} onValueChange={setRouteFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all")}</SelectItem>
                  {reportData.filters.routes.map((r) => (
                    <SelectItem key={r.routeId} value={r.routeId}>
                      {r.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Departure City */}
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">
                {t("trips.filter_city")}
              </label>
              <Select value={cityFilter} onValueChange={setCityFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all")}</SelectItem>
                  {reportData.filters.departureCities.map((c) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Date Range */}
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-xs font-medium text-muted-foreground mb-1 block">
                  {t("report.date_from")}
                </label>
                <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground mb-1 block">
                  {t("report.date_to")}
                </label>
                <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* Results Table */}
      <Card>
        <div className="p-4 pb-3 border-b">
          <div className="text-sm font-medium flex items-center gap-2">
            {t("report.results")}
            <Badge variant="secondary" className="text-[10px]">
              {filteredTrips.length}
            </Badge>
          </div>
        </div>
        <div className="p-4">
          {filteredTrips.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon"><CalendarIcon /></EmptyMedia>
                <EmptyTitle>{t("trips.no_results")}</EmptyTitle>
                <EmptyDescription>{t("trips.no_results_desc", { defaultValue: "Try adjusting your filters or date range." })}</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <div className="overflow-x-auto -mx-4">
              <table className="w-full text-xs min-w-[900px]">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("trips.col_route")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">Bus</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("trips.col_departure")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("trips.col_status")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("trips.col_seats")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("trips.col_bookings")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("trips.col_occupancy")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("trips.col_revenue")}</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredTrips.map((trip) => (
                    <tr key={trip._id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="py-2.5 px-3">
                        <div className="font-medium">{trip.originCity} → {trip.destinationCity}</div>
                      </td>
                      <td className="py-2.5 px-3">
                        <div className="flex items-center gap-1.5">
                          <BusIcon className="w-3 h-3 text-muted-foreground" />
                          <span>{trip.busName}</span>
                        </div>
                        <div className="text-muted-foreground text-[10px]">{trip.busPlateNumber}</div>
                      </td>
                      <td className="py-2.5 px-3 whitespace-nowrap">
                        {format(new Date(trip.departureTime), "dd/MM/yy HH:mm")}
                      </td>
                      <td className="py-2.5 px-3">
                        <Badge variant={statusVariant(trip.status)} className="text-[10px]">
                          {t(`trips.status_${trip.status}`)}
                        </Badge>
                      </td>
                      <td className="py-2.5 px-3 text-center">{trip.totalSeats}</td>
                      <td className="py-2.5 px-3 text-center font-medium">{trip.bookingCount}</td>
                      <td className="py-2.5 px-3">
                        <div className="flex items-center gap-2">
                          <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden max-w-[60px]">
                            <div
                              className={cn(
                                "h-full rounded-full",
                                trip.occupancyRate >= 80 ? "bg-green-500" :
                                trip.occupancyRate >= 50 ? "bg-yellow-500" : "bg-red-400"
                              )}
                              style={{ width: `${Math.min(trip.occupancyRate, 100)}%` }}
                            />
                          </div>
                          <span className="text-[10px] text-muted-foreground">{trip.occupancyRate}%</span>
                        </div>
                      </td>
                      <td className="py-2.5 px-3 font-medium whitespace-nowrap">
                        {trip.revenue.toLocaleString()} {trip.currency}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}
