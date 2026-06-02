import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { useState, useMemo } from "react";
import { format } from "date-fns";
import {
  SearchIcon,
  UsersIcon,
  TrendingUpIcon,
  RepeatIcon,
  FileSpreadsheetIcon,
  MailIcon,
  PhoneIcon,
} from "lucide-react";
import { Card } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";

import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";

type TravelerRow = {
  _id: string;
  name: string;
  phone: string | undefined;
  email: string | undefined;
  totalBookings: number;
  totalSpent: number;
  currency: string;
  lastTripDate: string | null;
  lastRoute: string | null;
};

function exportCSV(travelers: TravelerRow[], t: (key: string) => string) {
  const headers = [
    t("travelers.col_name"),
    t("travelers.col_email"),
    t("travelers.col_phone"),
    t("travelers.col_bookings"),
    t("travelers.col_spent"),
    t("travelers.col_currency"),
    t("travelers.col_last_trip"),
    t("travelers.col_last_route"),
  ];

  const rows = travelers.map((tr) => [
    tr.name,
    tr.email ?? "",
    tr.phone ?? "",
    String(tr.totalBookings),
    String(tr.totalSpent),
    tr.currency,
    tr.lastTripDate ? format(new Date(tr.lastTripDate), "dd/MM/yyyy") : "",
    tr.lastRoute ?? "",
  ]);

  const csvContent = [headers, ...rows]
    .map((row) => row.map((cell) => `"${cell.replace(/"/g, '""')}"`).join(","))
    .join("\n");

  const blob = new Blob(["\uFEFF" + csvContent], { type: "text/csv;charset=utf-8;" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `voyageurs-${format(new Date(), "yyyy-MM-dd")}.csv`;
  link.click();
  URL.revokeObjectURL(link.href);
}

export default function TravelersPage() {
  const { t } = useTranslation("analytics");
  const travelers = useQuery(api.analytics.getTravelers, {});

  const [search, setSearch] = useState("");

  const filteredTravelers = useMemo(() => {
    if (!travelers) return [];
    if (!search.trim()) return travelers;
    const q = search.toLowerCase();
    return travelers.filter(
      (tr) =>
        tr.name.toLowerCase().includes(q) ||
        (tr.email && tr.email.toLowerCase().includes(q)) ||
        (tr.phone && tr.phone.includes(q))
    );
  }, [travelers, search]);

  const summary = useMemo(() => {
    if (!filteredTravelers.length) return { total: 0, totalSpent: 0, avgBookings: 0, currency: "XAF" };
    const total = filteredTravelers.length;
    const totalSpent = filteredTravelers.reduce((sum, tr) => sum + tr.totalSpent, 0);
    const avgBookings = Math.round(filteredTravelers.reduce((sum, tr) => sum + tr.totalBookings, 0) / total * 10) / 10;
    const currency = filteredTravelers[0]?.currency ?? "XAF";
    return { total, totalSpent, avgBookings, currency };
  }, [filteredTravelers]);

  if (travelers === undefined) {
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
          <h1 className="text-xl font-extrabold tracking-tight">{t("travelers.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("travelers.desc")}</p>
        </div>
        <Button
          size="sm"
          variant="secondary"
          onClick={() => exportCSV(filteredTravelers, t)}
          disabled={filteredTravelers.length === 0}
          className="cursor-pointer shrink-0 text-xs"
        >
          <FileSpreadsheetIcon className="w-3.5 h-3.5 mr-1.5" />
          CSV
        </Button>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-cyan-50 dark:bg-cyan-950/30 flex items-center justify-center">
              <UsersIcon className="w-4 h-4 text-cyan-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{t("travelers.total_travelers")}</p>
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
              <p className="text-xs text-muted-foreground">{t("travelers.total_spent")}</p>
              <p className="text-lg font-bold">
                {summary.totalSpent.toLocaleString()} {summary.currency}
              </p>
            </div>
          </div>
        </Card>
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-orange-50 dark:bg-orange-950/30 flex items-center justify-center">
              <RepeatIcon className="w-4 h-4 text-orange-600" />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">{t("travelers.avg_bookings")}</p>
              <p className="text-lg font-bold">{summary.avgBookings}</p>
            </div>
          </div>
        </Card>
      </div>

      {/* Search */}
      <div className="relative">
        <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder={t("travelers.search_placeholder")}
          className="pl-9"
        />
      </div>

      {/* Results Table */}
      <Card>
        <div className="p-4 pb-3 border-b">
          <div className="text-sm font-medium flex items-center gap-2">
            {t("report.results")}
            <Badge variant="secondary" className="text-[10px]">
              {filteredTravelers.length}
            </Badge>
          </div>
        </div>
        <div className="p-4">
          {filteredTravelers.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon"><UsersIcon /></EmptyMedia>
                <EmptyTitle>{t("travelers.no_results")}</EmptyTitle>
                <EmptyDescription>{t("travelers.no_results_desc", { defaultValue: "Try adjusting your search terms." })}</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <div className="overflow-x-auto -mx-4">
              <table className="w-full text-xs min-w-[750px]">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("travelers.col_name")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("travelers.col_contact")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("travelers.col_bookings")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("travelers.col_spent")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("travelers.col_last_trip")}</th>
                    <th className="pb-2 px-3 font-medium text-muted-foreground">{t("travelers.col_last_route")}</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredTravelers.map((traveler) => (
                    <tr key={traveler._id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="py-2.5 px-3">
                        <div className="font-medium">{traveler.name}</div>
                      </td>
                      <td className="py-2.5 px-3">
                        {traveler.email && (
                          <div className="flex items-center gap-1 text-muted-foreground">
                            <MailIcon className="w-3 h-3" />
                            <span className="truncate max-w-[140px]">{traveler.email}</span>
                          </div>
                        )}
                        {traveler.phone && (
                          <div className="flex items-center gap-1 text-muted-foreground">
                            <PhoneIcon className="w-3 h-3" />
                            <span>{traveler.phone}</span>
                          </div>
                        )}
                        {!traveler.email && !traveler.phone && (
                          <span className="text-muted-foreground italic">—</span>
                        )}
                      </td>
                      <td className="py-2.5 px-3 text-center">
                        <Badge variant="secondary" className="text-[10px]">
                          {traveler.totalBookings}
                        </Badge>
                      </td>
                      <td className="py-2.5 px-3 font-medium whitespace-nowrap">
                        {traveler.totalSpent.toLocaleString()} {traveler.currency}
                      </td>
                      <td className="py-2.5 px-3 text-muted-foreground whitespace-nowrap">
                        {traveler.lastTripDate
                          ? format(new Date(traveler.lastTripDate), "dd/MM/yy")
                          : "—"}
                      </td>
                      <td className="py-2.5 px-3 text-muted-foreground">
                        {traveler.lastRoute ?? "—"}
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
