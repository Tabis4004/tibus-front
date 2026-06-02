import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { useState, useMemo, useCallback } from "react";
import { useParams } from "react-router-dom";
import { format } from "date-fns";
import { generateReceiptPDF, type ReceiptData } from "@/lib/receipt-pdf.ts";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import {
  DownloadIcon,
  FilterIcon,
  XIcon,
  SearchIcon,
  TicketIcon,
  TrendingUpIcon,
  PackageIcon,
  FileSpreadsheetIcon,
  FileTextIcon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
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

type TicketRow = {
  _id: string;
  _creationTime: number;
  bookingReference: string;
  passengerName: string;
  passengerPhone: string | undefined;
  status: string;
  paymentStatus: string | undefined;
  totalPrice: number;
  currency: string;
  parcelCount: number | undefined;
  parcelWeight: number | undefined;
  parcelAmount: number | undefined;
  sellerId: string | null;
  sellerName: string | null;
  tripId: string;
  routeId: string;
  busId: string;
  busName: string;
  busPlateNumber: string;
  originCity: string;
  destinationCity: string;
  departureTime: string;
  isReservation: boolean;
};

/** Export filtered tickets as CSV */
function exportCSV(tickets: TicketRow[]) {
  const headers = [
    "Reference", "Passager", "Telephone", "Trajet", "Depart",
    "Bus", "Vendeur", "Type", "Statut", "Montant", "Devise",
    "Colis", "Poids colis", "Montant colis", "Date creation",
  ];

  const rows = tickets.map((tk) => [
    tk.bookingReference,
    tk.passengerName,
    tk.passengerPhone ?? "",
    `${tk.originCity} - ${tk.destinationCity}`,
    format(new Date(tk.departureTime), "dd/MM/yyyy HH:mm"),
    `${tk.busName} (${tk.busPlateNumber})`,
    tk.sellerName ?? "Online",
    tk.isReservation ? "Reservation" : "Guichet",
    tk.status,
    String(tk.totalPrice),
    tk.currency,
    String(tk.parcelCount ?? 0),
    String(tk.parcelWeight ?? 0),
    String(tk.parcelAmount ?? 0),
    format(new Date(tk._creationTime), "dd/MM/yyyy HH:mm"),
  ]);

  const csvContent = [headers, ...rows]
    .map((row) => row.map((cell) => `"${cell.replace(/"/g, '""')}"`).join(","))
    .join("\n");

  const blob = new Blob(["\uFEFF" + csvContent], { type: "text/csv;charset=utf-8;" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `rapport-billets-${format(new Date(), "yyyy-MM-dd")}.csv`;
  link.click();
  URL.revokeObjectURL(link.href);
}

/** Export filtered tickets as PDF report */
function exportPDFReport(tickets: TicketRow[], companyName: string) {
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });

  // Header band
  doc.setFillColor(75, 0, 130);
  doc.rect(0, 0, 297, 20, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  doc.text(`${companyName} — Rapport des Billets`, 14, 13);
  doc.setFontSize(8);
  doc.setFont("helvetica", "normal");
  doc.text(`Genere le ${format(new Date(), "dd/MM/yyyy HH:mm")} | ${tickets.length} billets`, 14, 18);

  // Table
  const head = [["Ref", "Passager", "Trajet", "Depart", "Bus", "Vendeur", "Type", "Statut", "Montant"]];
  const body = tickets.map((tk) => [
    tk.bookingReference,
    tk.passengerName,
    `${tk.originCity} → ${tk.destinationCity}`,
    format(new Date(tk.departureTime), "dd/MM/yy HH:mm"),
    tk.busName,
    tk.sellerName ?? "Online",
    tk.isReservation ? "Reservation" : "Guichet",
    tk.status,
    `${tk.totalPrice.toLocaleString()} ${tk.currency}`,
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

  // Summary
  const totalRevenue = tickets
    .filter((tk) => tk.status === "confirmed" || tk.status === "collected")
    .reduce((sum, tk) => sum + tk.totalPrice, 0);
  const currency = tickets[0]?.currency ?? "XAF";
  const finalY = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 8;
  doc.setTextColor(0, 0, 0);
  doc.setFontSize(10);
  doc.setFont("helvetica", "bold");
  doc.text(`Revenu Total: ${totalRevenue.toLocaleString()} ${currency}`, 14, finalY);
  doc.setFontSize(7);
  doc.setFont("helvetica", "normal");
  doc.text("Powered By Tibus", 14, finalY + 5);

  doc.save(`rapport-billets-${format(new Date(), "yyyy-MM-dd")}.pdf`);
}

export default function TicketReportsPage() {
  const { t } = useTranslation("analytics");
  const { lng } = useParams<{ lng: string }>();
  const reportData = useQuery(api.analytics.getTicketReport, {});
  const company = useQuery(api.companies.getMyCompany, {});

  // Filter state
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [sellerFilter, setSellerFilter] = useState("all");
  const [busFilter, setBusFilter] = useState("all");
  const [routeFilter, setRouteFilter] = useState("all");
  const [cityFilter, setCityFilter] = useState("all");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [typeFilter, setTypeFilter] = useState("all");
  const [showFilters, setShowFilters] = useState(false);

  // Filtered tickets
  const filteredTickets = useMemo(() => {
    if (!reportData) return [];
    let tickets = reportData.tickets;

    // Search by name, reference, phone
    if (search.trim()) {
      const q = search.toLowerCase();
      tickets = tickets.filter(
        (tk) =>
          tk.passengerName.toLowerCase().includes(q) ||
          tk.bookingReference.toLowerCase().includes(q) ||
          (tk.passengerPhone && tk.passengerPhone.includes(q))
      );
    }

    if (statusFilter !== "all") {
      tickets = tickets.filter((tk) => tk.status === statusFilter);
    }
    if (sellerFilter !== "all") {
      tickets = tickets.filter((tk) => tk.sellerId === sellerFilter);
    }
    if (busFilter !== "all") {
      tickets = tickets.filter((tk) => tk.busId === busFilter);
    }
    if (routeFilter !== "all") {
      tickets = tickets.filter((tk) => tk.routeId === routeFilter);
    }
    if (cityFilter !== "all") {
      tickets = tickets.filter((tk) => tk.originCity === cityFilter);
    }
    if (typeFilter === "reservation") {
      tickets = tickets.filter((tk) => tk.isReservation);
    } else if (typeFilter === "seller_sale") {
      tickets = tickets.filter((tk) => !tk.isReservation);
    }

    // Date range
    if (dateFrom) {
      const from = new Date(dateFrom);
      from.setHours(0, 0, 0, 0);
      tickets = tickets.filter((tk) => new Date(tk._creationTime) >= from);
    }
    if (dateTo) {
      const to = new Date(dateTo);
      to.setHours(23, 59, 59, 999);
      tickets = tickets.filter((tk) => new Date(tk._creationTime) <= to);
    }

    return tickets;
  }, [reportData, search, statusFilter, sellerFilter, busFilter, routeFilter, cityFilter, typeFilter, dateFrom, dateTo]);

  // Summary stats
  const summary = useMemo(() => {
    const total = filteredTickets.length;
    const revenue = filteredTickets
      .filter((tk) => tk.status === "confirmed" || tk.status === "collected")
      .reduce((sum, tk) => sum + tk.totalPrice, 0);
    const parcelRevenue = filteredTickets.reduce((sum, tk) => sum + (tk.parcelAmount ?? 0), 0);
    const currency = filteredTickets[0]?.currency ?? "XAF";
    return { total, revenue, parcelRevenue, currency };
  }, [filteredTickets]);

  // Active filter count
  const activeFilters = useMemo(() => {
    let count = 0;
    if (statusFilter !== "all") count++;
    if (sellerFilter !== "all") count++;
    if (busFilter !== "all") count++;
    if (routeFilter !== "all") count++;
    if (cityFilter !== "all") count++;
    if (typeFilter !== "all") count++;
    if (dateFrom) count++;
    if (dateTo) count++;
    return count;
  }, [statusFilter, sellerFilter, busFilter, routeFilter, cityFilter, typeFilter, dateFrom, dateTo]);

  const clearFilters = useCallback(() => {
    setSearch("");
    setStatusFilter("all");
    setSellerFilter("all");
    setBusFilter("all");
    setRouteFilter("all");
    setCityFilter("all");
    setTypeFilter("all");
    setDateFrom("");
    setDateTo("");
  }, []);

  /** Download individual ticket as corporate PDF receipt (A4) */
  const handleDownloadTicketPDF = useCallback((tk: TicketRow) => {
    const verifyUrl = `${window.location.origin}/${lng ?? "fr"}/verify/${tk.bookingReference}`;
    const receiptData: ReceiptData = {
      bookingReference: tk.bookingReference,
      passengerName: tk.passengerName,
      passengerPhone: tk.passengerPhone,
      companyName: company?.name ?? "Transport Company",
      boardingMessage: company?.boardingMessage,
      originCity: tk.originCity,
      originStation: tk.originCity,
      destCity: tk.destinationCity,
      destStation: tk.destinationCity,
      departureTime: format(new Date(tk.departureTime), "dd/MM/yyyy HH:mm"),
      arrivalTime: "-",
      busName: tk.busName,
      busPlateNumber: tk.busPlateNumber,
      ticketPrice: tk.totalPrice - (tk.parcelAmount ?? 0),
      currency: tk.currency,
      parcelCount: tk.parcelCount,
      parcelWeight: tk.parcelWeight,
      parcelAmount: tk.parcelAmount,
      totalPrice: tk.totalPrice,
      issuedAt: format(new Date(tk._creationTime), "dd/MM/yyyy HH:mm"),
      verifyUrl,
    };
    generateReceiptPDF(receiptData, "a4");
  }, [company, lng]);

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
          <h1 className="text-xl font-extrabold tracking-tight">{t("report.title", { defaultValue: "Rapport des Billets" })}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("report.desc", { defaultValue: "Filtrez, triez et exportez vos données de vente" })}</p>
        </div>
        <div className="flex gap-2">
          <Button
            size="sm"
            variant="secondary"
            onClick={() => exportCSV(filteredTickets)}
            disabled={filteredTickets.length === 0}
            className="cursor-pointer shrink-0 text-xs"
          >
            <FileSpreadsheetIcon className="w-3.5 h-3.5 mr-1.5" />
            CSV
          </Button>
          <Button
            size="sm"
            onClick={() => exportPDFReport(filteredTickets, company?.name ?? "Company")}
            disabled={filteredTickets.length === 0}
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
            <div className="w-9 h-9 rounded-lg bg-blue-50 dark:bg-blue-950/30 flex items-center justify-center">
              <TicketIcon className="w-4 h-4 text-blue-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{t("report.total_tickets", { defaultValue: "Total billets" })}</p>
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
              <p className="text-xs text-muted-foreground">{t("report.total_revenue", { defaultValue: "Revenu total" })}</p>
              <p className="text-lg font-bold">
                {summary.revenue.toLocaleString()} {summary.currency}
              </p>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-orange-50 dark:bg-orange-950/30 flex items-center justify-center">
              <PackageIcon className="w-4 h-4 text-orange-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{t("report.parcel_revenue", { defaultValue: "Revenu colis" })}</p>
              <p className="text-lg font-bold">
                {summary.parcelRevenue.toLocaleString()} {summary.currency}
              </p>
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
            placeholder={t("report.search_placeholder", { defaultValue: "Rechercher par nom, référence, téléphone..." })}
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
          {t("report.filters", { defaultValue: "Filtres" })}
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
            {t("report.clear_filters", { defaultValue: "Effacer" })}
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
                {t("report.filter_status", { defaultValue: "Statut" })}
              </label>
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all", { defaultValue: "Tous" })}</SelectItem>
                  <SelectItem value="confirmed">Confirmé</SelectItem>
                  <SelectItem value="collected">Collecté</SelectItem>
                  <SelectItem value="pending_payment">En attente</SelectItem>
                  <SelectItem value="cancelled">Annulé</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Type */}
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">
                {t("report.filter_type", { defaultValue: "Type" })}
              </label>
              <Select value={typeFilter} onValueChange={setTypeFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all", { defaultValue: "Tous" })}</SelectItem>
                  <SelectItem value="reservation">Reservation (Online)</SelectItem>
                  <SelectItem value="seller_sale">Guichet (Vendeur)</SelectItem>
                </SelectContent>
              </Select>
            </div>

            {/* Seller */}
            <div>
              <label className="text-xs font-medium text-muted-foreground mb-1 block">
                {t("report.filter_seller", { defaultValue: "Vendeur" })}
              </label>
              <Select value={sellerFilter} onValueChange={setSellerFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all", { defaultValue: "Tous" })}</SelectItem>
                  {reportData.filters.sellers.map((s) => (
                    <SelectItem key={s._id} value={s._id}>
                      {s.name}
                    </SelectItem>
                  ))}
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
                  <SelectItem value="all">{t("report.all", { defaultValue: "Tous" })}</SelectItem>
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
                {t("report.filter_route", { defaultValue: "Trajet" })}
              </label>
              <Select value={routeFilter} onValueChange={setRouteFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all", { defaultValue: "Tous" })}</SelectItem>
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
                {t("report.filter_city", { defaultValue: "Ville départ" })}
              </label>
              <Select value={cityFilter} onValueChange={setCityFilter}>
                <SelectTrigger className="cursor-pointer">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("report.all", { defaultValue: "Tous" })}</SelectItem>
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
                  {t("report.date_from", { defaultValue: "Du" })}
                </label>
                <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground mb-1 block">
                  {t("report.date_to", { defaultValue: "Au" })}
                </label>
                <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* Results Table */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium flex items-center gap-2">
            {t("report.results", { defaultValue: "Résultats" })}
            <Badge variant="secondary" className="text-[10px]">
              {filteredTickets.length}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {filteredTickets.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon"><TicketIcon /></EmptyMedia>
                <EmptyTitle>{t("report.no_results", { defaultValue: "Aucun billet trouvé avec ces filtres" })}</EmptyTitle>
                <EmptyDescription>{t("report.no_results_desc", { defaultValue: "Try adjusting your filters or search terms." })}</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <div className="overflow-x-auto -mx-6">
              <table className="w-full text-xs min-w-[1000px]">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-2 px-3 font-medium text-muted-foreground">Ref</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("report.col_passenger", { defaultValue: "Passager" })}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("report.col_route", { defaultValue: "Trajet" })}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">Bus</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("report.col_departure", { defaultValue: "Départ" })}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("report.col_seller", { defaultValue: "Vendeur" })}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("report.col_amount", { defaultValue: "Montant" })}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("report.col_status", { defaultValue: "Statut" })}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("report.col_date", { defaultValue: "Date" })}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground"></th>
                  </tr>
                </thead>
                <tbody>
                  {filteredTickets.map((ticket) => (
                    <tr key={ticket._id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="py-2 px-3 font-mono text-[10px]">{ticket.bookingReference}</td>
                      <td className="py-2 px-3">
                        <div className="font-medium">{ticket.passengerName}</div>
                        {ticket.passengerPhone && (
                          <div className="text-muted-foreground text-[10px]">{ticket.passengerPhone}</div>
                        )}
                      </td>
                      <td className="py-2 px-3">
                        {ticket.originCity} → {ticket.destinationCity}
                      </td>
                      <td className="py-2 px-3">
                        <div>{ticket.busName}</div>
                        <div className="text-muted-foreground text-[10px]">{ticket.busPlateNumber}</div>
                      </td>
                      <td className="py-2 px-3 whitespace-nowrap">
                        {format(new Date(ticket.departureTime), "dd/MM/yy HH:mm")}
                      </td>
                      <td className="py-2 px-3">
                        {ticket.sellerName ? (
                          <span>{ticket.sellerName}</span>
                        ) : (
                          <span className="text-muted-foreground italic">Online</span>
                        )}
                      </td>
                      <td className="py-2 px-3 font-medium whitespace-nowrap">
                        {ticket.totalPrice.toLocaleString()} {ticket.currency}
                        {(ticket.parcelAmount ?? 0) > 0 && (
                          <div className="text-[10px] text-orange-600">
                            +{ticket.parcelAmount?.toLocaleString()} (colis)
                          </div>
                        )}
                      </td>
                      <td className="py-2 px-3">
                        <Badge variant={statusVariant(ticket.status)} className="text-[10px]">
                          {ticket.status}
                        </Badge>
                      </td>
                      <td className="py-2 px-3 text-muted-foreground whitespace-nowrap">
                        {format(new Date(ticket._creationTime), "dd/MM/yy HH:mm")}
                      </td>
                      <td className="py-2 px-3">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-6 w-6 p-0 cursor-pointer"
                          title="Télécharger reçu A4"
                          onClick={() => handleDownloadTicketPDF(ticket)}
                        >
                          <DownloadIcon className="w-3.5 h-3.5" />
                        </Button>
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
