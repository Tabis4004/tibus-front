import { useCallback, useEffect, useMemo, useState } from "react";
import { format, parseISO, endOfDay, startOfDay, subDays, startOfMonth } from "date-fns";
import { toast } from "sonner";
import { BanIcon, PrinterIcon, RefreshCwIcon, SearchIcon, XIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog.tsx";
import { useDebounce } from "@/hooks/use-debounce.ts";
import {
  cancelCompanyTicketSupabase,
  listCompanyTicketSalesSupabase,
  previewTicketCancellationSupabase,
  type CancellationPreview,
  type CompanyTicketSaleRow,
  type CompanyTicketSalesFilters,
} from "@/lib/supabase/cancellation.ts";
import { getCompanyGuaranteeFundSupabase } from "@/lib/supabase/guarantee-fund.ts";

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

const CHANNEL_LABELS: Record<string, string> = {
  traveler: "Voyageur",
  seller_reservation: "Réservation tiers",
  counter_sale: "Guichet",
};

type SaleChannelFilter = "all" | "traveler" | "counter_sale" | "seller_reservation";
type PeriodFilter = "all" | "today" | "7d" | "30d" | "month";

function periodToRange(period: PeriodFilter): Pick<CompanyTicketSalesFilters, "createdFrom" | "createdTo"> {
  const now = new Date();
  if (period === "all") return { createdFrom: null, createdTo: null };
  if (period === "today") {
    return {
      createdFrom: startOfDay(now).toISOString(),
      createdTo: endOfDay(now).toISOString(),
    };
  }
  if (period === "7d") {
    return {
      createdFrom: startOfDay(subDays(now, 6)).toISOString(),
      createdTo: endOfDay(now).toISOString(),
    };
  }
  if (period === "30d") {
    return {
      createdFrom: startOfDay(subDays(now, 29)).toISOString(),
      createdTo: endOfDay(now).toISOString(),
    };
  }
  return {
    createdFrom: startOfMonth(now).toISOString(),
    createdTo: endOfDay(now).toISOString(),
  };
}

export default function CompanySalesLedger({
  companyId,
  canCancel = false,
  onReprint,
}: {
  companyId: string;
  canCancel?: boolean;
  onReprint?: (row: CompanyTicketSaleRow) => void;
}) {
  const [rows, setRows] = useState<CompanyTicketSaleRow[] | undefined>(undefined);
  const [loading, setLoading] = useState(false);
  const [target, setTarget] = useState<CompanyTicketSaleRow | null>(null);
  const [preview, setPreview] = useState<CancellationPreview | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [cancelling, setCancelling] = useState(false);

  const [channel, setChannel] = useState<SaleChannelFilter>("all");
  const [period, setPeriod] = useState<PeriodFilter>("all");
  const [departureDate, setDepartureDate] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [debouncedSearch] = useDebounce(searchInput, 350);
  const [guaranteeBalance, setGuaranteeBalance] = useState<string | null>(null);

  useEffect(() => {
    void getCompanyGuaranteeFundSupabase(companyId)
      .then((fund) => {
        const prefix = fund.balance < 0 ? "⚠ " : "";
        const suffix = fund.allowNegative ? " (négatif autorisé)" : "";
        setGuaranteeBalance(`${prefix}${fund.balance.toLocaleString()} ${fund.currency}${suffix}`);
      })
      .catch(() => setGuaranteeBalance(null));
  }, [companyId]);

  const filters = useMemo((): CompanyTicketSalesFilters => {
    const range = periodToRange(period);
    let departureFrom: string | null = null;
    let departureTo: string | null = null;
    if (departureDate) {
      const day = parseISO(`${departureDate}T00:00:00`);
      departureFrom = startOfDay(day).toISOString();
      departureTo = endOfDay(day).toISOString();
    }
    return {
      saleChannel: channel === "all" ? null : channel,
      createdFrom: range.createdFrom,
      createdTo: range.createdTo,
      departureFrom,
      departureTo,
      search: debouncedSearch.trim() || null,
    };
  }, [channel, period, departureDate, debouncedSearch]);

  const hasActiveFilters =
    channel !== "all" ||
    period !== "all" ||
    Boolean(departureDate) ||
    Boolean(searchInput.trim());

  const load = useCallback(() => {
    setLoading(true);
    setRows(undefined);
    void listCompanyTicketSalesSupabase(companyId, filters)
      .then(setRows)
      .catch((err) => toast.error(err instanceof Error ? err.message : "Chargement impossible"))
      .finally(() => setLoading(false));
  }, [companyId, filters]);

  useEffect(() => {
    load();
  }, [load]);

  const resetFilters = () => {
    setChannel("all");
    setPeriod("all");
    setDepartureDate("");
    setSearchInput("");
  };

  const openCancel = async (row: CompanyTicketSaleRow) => {
    setTarget(row);
    setPreview(null);
    setPreviewLoading(true);
    try {
      const result = await previewTicketCancellationSupabase(row.bookingId);
      setPreview(result);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Prévisualisation impossible");
      setTarget(null);
    } finally {
      setPreviewLoading(false);
    }
  };

  const confirmCancel = async () => {
    if (!target) return;
    setCancelling(true);
    try {
      const result = await cancelCompanyTicketSupabase(target.bookingId);
      toast.success(
        `Annulé · remboursement ${result.refundAmount.toLocaleString()} · pénalité ${result.penaltyAmount.toLocaleString()}`,
      );
      setTarget(null);
      setPreview(null);
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Annulation impossible");
    } finally {
      setCancelling(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-lg font-bold">Journal des ventes</h2>
          <p className="text-sm text-muted-foreground">
            Réservations en ligne, guichet et tiers — toutes les ventes de la compagnie.
          </p>
          {guaranteeBalance && (
            <p className="text-xs text-muted-foreground mt-1">
              Fond de garantie : <span className="font-semibold text-foreground">{guaranteeBalance}</span>
            </p>
          )}
        </div>
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>
          <RefreshCwIcon className="w-4 h-4 mr-1.5" />
          Actualiser
        </Button>
      </div>

      <div className="rounded-xl border p-4 space-y-3 bg-muted/20">
        <div className="relative">
          <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Rechercher par nom voyageur ou n° de ticket…"
            className="pl-9"
          />
        </div>

        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="space-y-1.5">
            <Label className="text-xs">Canal</Label>
            <Select value={channel} onValueChange={(v) => setChannel(v as SaleChannelFilter)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Tous les canaux</SelectItem>
                <SelectItem value="traveler">Voyageur</SelectItem>
                <SelectItem value="counter_sale">Guichet</SelectItem>
                <SelectItem value="seller_reservation">Réservation tiers</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs">Période de vente</Label>
            <Select value={period} onValueChange={(v) => setPeriod(v as PeriodFilter)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Toutes périodes</SelectItem>
                <SelectItem value="today">Aujourd&apos;hui</SelectItem>
                <SelectItem value="7d">7 derniers jours</SelectItem>
                <SelectItem value="30d">30 derniers jours</SelectItem>
                <SelectItem value="month">Ce mois</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs">Date de départ</Label>
            <Input
              type="date"
              value={departureDate}
              onChange={(e) => setDepartureDate(e.target.value)}
            />
          </div>

          <div className="flex items-end">
            {hasActiveFilters && (
              <Button variant="ghost" size="sm" className="w-full" onClick={resetFilters}>
                <XIcon className="w-4 h-4 mr-1.5" />
                Réinitialiser
              </Button>
            )}
          </div>
        </div>
      </div>

      {rows === undefined ? (
        <Skeleton className="h-48 w-full" />
      ) : rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aucune vente ne correspond aux filtres.</p>
      ) : (
        <>
          <p className="text-xs text-muted-foreground">{rows.length} vente(s) affichée(s)</p>
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">Réf.</th>
                  <th className="px-3 py-2">Voyageur</th>
                  <th className="px-3 py-2">Trajet</th>
                  <th className="px-3 py-2">Départ</th>
                  <th className="px-3 py-2">Canal</th>
                  <th className="px-3 py-2">Vendeur</th>
                  <th className="px-3 py-2">M</th>
                  <th className="px-3 py-2">Statut</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((row) => (
                  <tr key={row.bookingId}>
                    <td className="px-3 py-2 font-mono text-xs">{row.reference}</td>
                    <td className="px-3 py-2">{row.passengerName}</td>
                    <td className="px-3 py-2">{row.routeLabel}</td>
                    <td className="px-3 py-2 whitespace-nowrap">
                      {fmt(row.departureTime, "dd/MM/yyyy HH:mm")}
                    </td>
                    <td className="px-3 py-2">
                      {CHANNEL_LABELS[row.saleChannel] ?? row.saleChannel}
                    </td>
                    <td className="px-3 py-2">{row.sellerName ?? "—"}</td>
                    <td className="px-3 py-2 font-medium">
                      {row.ticketAmount.toLocaleString()} {row.currency}
                    </td>
                    <td className="px-3 py-2">
                      <Badge variant={row.ticketStatus === "cancelled" ? "destructive" : "secondary"}>
                        {row.ticketStatus}
                      </Badge>
                    </td>
                    <td className="px-3 py-2">
                      <div className="flex flex-wrap gap-1.5">
                        {onReprint && row.ticketStatus !== "cancelled" && (
                          <Button size="sm" variant="outline" onClick={() => onReprint(row)}>
                            <PrinterIcon className="w-3.5 h-3.5 mr-1" />
                            Reimprimer
                          </Button>
                        )}
                        {canCancel && row.canCancel && (
                          <Button size="sm" variant="outline" onClick={() => openCancel(row)}>
                            <BanIcon className="w-4 h-4 mr-1" />
                            Annuler
                          </Button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <AlertDialog open={Boolean(target)} onOpenChange={(open) => !open && setTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirmer l&apos;annulation</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-2 text-sm">
                {previewLoading && <p>Calcul de la pénalité…</p>}
                {preview && (
                  <>
                    <p>
                      Encaissement M : <strong>{preview.nominalAmount.toLocaleString()}</strong>
                    </p>
                    <p>
                      Pénalité P : <strong>{preview.penaltyAmount.toLocaleString()}</strong>
                      {" "}({preview.penaltyType === "percent" ? `${preview.penaltyValue}%` : "fixe"}
                      {preview.tierLabel ? ` · ${preview.tierLabel}` : ""})
                    </p>
                    <p>
                      Remboursement : <strong>{preview.refundAmount.toLocaleString()}</strong>
                    </p>
                    <p className="text-muted-foreground">
                      {Math.round(preview.hoursBeforeDeparture)} h avant le départ
                      {preview.staffOnly ? " · zone critique (vendeur/owner)" : ""}
                    </p>
                  </>
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Fermer</AlertDialogCancel>
            <AlertDialogAction
              disabled={!preview?.canExecute || cancelling || previewLoading}
              onClick={confirmCancel}
            >
              {cancelling ? "Annulation…" : "Confirmer l'annulation"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
