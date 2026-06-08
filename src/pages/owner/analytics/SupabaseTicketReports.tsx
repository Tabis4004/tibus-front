import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { format } from "date-fns";
import { SearchIcon, TicketIcon } from "lucide-react";
import { Card, CardContent, CardHeader } from "@/components/ui/card.tsx";
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
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";
import {
  getOwnerTicketReportSupabase,
  type OwnerTicketReport,
  type OwnerTicketReportRow,
} from "@/lib/supabase/owner-reports";

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

export default function SupabaseTicketReports() {
  const { t } = useTranslation("analytics");
  const { appUserId } = useSupabaseAuth();
  const { companyId } = useOwnerCompany();
  const [report, setReport] = useState<OwnerTicketReport | undefined>(undefined);
  const [search, setSearch] = useState("");
  const [sellerFilter, setSellerFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");

  useEffect(() => {
    if (!appUserId || !companyId) return;
    let cancelled = false;
    void getOwnerTicketReportSupabase(appUserId, companyId)
      .then((data) => {
        if (!cancelled) setReport(data);
      })
      .catch(() => {
        if (!cancelled) setReport({ tickets: [], filters: { sellers: [], buses: [], routes: [], departureCities: [] } });
      });
    return () => {
      cancelled = true;
    };
  }, [appUserId, companyId]);

  useEffect(() => {
    if (!appUserId || !companyId) return;
    const onRefresh = () => {
      setReport(undefined);
      void getOwnerTicketReportSupabase(appUserId, companyId)
        .then(setReport)
        .catch(() =>
          setReport({ tickets: [], filters: { sellers: [], buses: [], routes: [], departureCities: [] } }),
        );
    };
    window.addEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
  }, [appUserId, companyId]);

  const filteredTickets = useMemo(() => {
    const tickets = report?.tickets ?? [];
    const q = search.trim().toLowerCase();
    return tickets.filter((ticket: OwnerTicketReportRow) => {
      if (sellerFilter !== "all" && ticket.sellerId !== sellerFilter) return false;
      if (statusFilter !== "all" && ticket.status !== statusFilter) return false;
      if (!q) return true;
      return (
        ticket.bookingReference.toLowerCase().includes(q) ||
        ticket.passengerName.toLowerCase().includes(q) ||
        (ticket.passengerPhone ?? "").includes(q)
      );
    });
  }, [report, search, sellerFilter, statusFilter]);

  const totalRevenue = filteredTickets.reduce((sum, t) => sum + t.totalPrice, 0);
  const currency = filteredTickets[0]?.currency ?? "XOF";

  return (
    <div className="max-w-6xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("report.tickets_title", { defaultValue: "Rapport billets" })}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          {t("report.tickets_desc", { defaultValue: "Historique des billets émis." })}
        </p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">Billets</p>
            <p className="text-2xl font-bold">{filteredTickets.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-xs text-muted-foreground">Revenus</p>
            <p className="text-2xl font-bold">
              {totalRevenue.toLocaleString()} {currency}
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <div className="flex flex-col sm:flex-row gap-3">
            <div className="relative flex-1">
              <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                className="pl-9"
                placeholder="Référence, passager..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <Select value={sellerFilter} onValueChange={setSellerFilter}>
              <SelectTrigger className="w-full sm:w-44">
                <SelectValue placeholder="Vendeur" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Tous vendeurs</SelectItem>
                {(report?.filters.sellers ?? []).map((s) => (
                  <SelectItem key={s._id} value={s._id}>
                    {s.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-full sm:w-40">
                <SelectValue placeholder="Statut" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Tous statuts</SelectItem>
                <SelectItem value="confirmed">Confirmé</SelectItem>
                <SelectItem value="pending_payment">En attente</SelectItem>
                <SelectItem value="collected">Collecté</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardHeader>
        <CardContent>
          {report === undefined ? (
            <Skeleton className="h-48 w-full" />
          ) : filteredTickets.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <TicketIcon />
                </EmptyMedia>
                <EmptyTitle>Aucun billet</EmptyTitle>
                <EmptyDescription>Ajustez les filtres ou vendez des billets.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-2 px-2">Réf.</th>
                    <th className="pb-2 px-2">Passager</th>
                    <th className="pb-2 px-2">Trajet</th>
                    <th className="pb-2 px-2">Départ</th>
                    <th className="pb-2 px-2">Montant</th>
                    <th className="pb-2 px-2">Statut</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredTickets.map((ticket) => (
                    <tr key={ticket._id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="py-2 px-2 font-mono">{ticket.bookingReference}</td>
                      <td className="py-2 px-2">{ticket.passengerName}</td>
                      <td className="py-2 px-2">
                        {ticket.originCity} → {ticket.destinationCity}
                      </td>
                      <td className="py-2 px-2 whitespace-nowrap">
                        {format(new Date(ticket.departureTime), "dd/MM/yy HH:mm")}
                      </td>
                      <td className="py-2 px-2 font-medium">
                        {ticket.totalPrice.toLocaleString()} {ticket.currency}
                      </td>
                      <td className="py-2 px-2">
                        <Badge variant={statusVariant(ticket.status)} className="text-[10px]">
                          {ticket.status}
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
