import { useCallback, useEffect, useState } from "react";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { CheckIcon, RefreshCwIcon, WalletIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  listCompanyStationCashReversalsSupabase,
  REVERSAL_STATUS_LABELS,
  validateStationCashReversalSupabase,
  type ReversalStatus,
  type StationCashReversal,
} from "@/lib/supabase/station-cash.ts";

const POLL_MS = 20_000;

function fmtDate(iso: string) {
  try {
    return format(parseISO(iso), "dd/MM/yyyy HH:mm");
  } catch {
    return iso;
  }
}

export default function StationCashReversalsPanel({
  companyId,
  gareId,
  canValidate = false,
}: {
  companyId: string;
  gareId?: string | null;
  canValidate?: boolean;
}) {
  const [statusFilter, setStatusFilter] = useState<"all" | ReversalStatus>("en_attente");
  const [rows, setRows] = useState<StationCashReversal[] | undefined>(undefined);
  const [actingId, setActingId] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(
    async (silent = false) => {
      if (!silent) setRows(undefined);
      else setRefreshing(true);
      try {
        const data = await listCompanyStationCashReversalsSupabase(
          companyId,
          statusFilter === "all" ? null : statusFilter,
        );
        setRows(
          gareId
            ? data.filter((row) => row.gareId === gareId)
            : data,
        );
      } catch (err) {
        toast.error(err instanceof Error ? err.message : "Chargement impossible");
        setRows([]);
      } finally {
        setRefreshing(false);
      }
    },
    [companyId, statusFilter, gareId],
  );

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => void load(true), POLL_MS);
    return () => window.clearInterval(timer);
  }, [load]);

  const handleValidate = async (reversalId: string) => {
    if (!window.confirm("Confirmer la réception des espèces et clôturer la caisse ?")) return;
    setActingId(reversalId);
    try {
      await validateStationCashReversalSupabase(reversalId);
      toast.success("Reversement validé — caisse clôturée");
      await load(true);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Validation impossible");
    } finally {
      setActingId(null);
    }
  };

  const pendingCount = rows?.filter((row) => row.status === "en_attente").length ?? 0;

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <CardTitle className="text-base flex items-center gap-2">
            <WalletIcon className="w-4 h-4" />
            Reversements caisse guichet
            {pendingCount > 0 ? (
              <Badge variant="secondary">{pendingCount} en attente</Badge>
            ) : null}
          </CardTitle>
          <div className="flex items-center gap-2">
            <Select
              value={statusFilter}
              onValueChange={(value) => setStatusFilter(value as "all" | ReversalStatus)}
            >
              <SelectTrigger className="w-[160px] h-8">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="en_attente">En attente</SelectItem>
                <SelectItem value="approuve_recu">Approuvés</SelectItem>
                <SelectItem value="all">Tous</SelectItem>
              </SelectContent>
            </Select>
            <Button
              size="sm"
              variant="outline"
              className="h-8 cursor-pointer"
              disabled={refreshing}
              onClick={() => void load(true)}
            >
              <RefreshCwIcon className={`w-3.5 h-3.5 mr-1.5 ${refreshing ? "animate-spin" : ""}`} />
              Actualiser
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {rows === undefined ? (
          <Skeleton className="h-40 w-full" />
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Aucun reversement pour ce filtre.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">Date</th>
                  <th className="px-3 py-2">Gare</th>
                  <th className="px-3 py-2">Guichetier</th>
                  <th className="px-3 py-2">Montant</th>
                  <th className="px-3 py-2">Solde caisse</th>
                  <th className="px-3 py-2">Statut</th>
                  {canValidate ? <th className="px-3 py-2" /> : null}
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((row) => (
                  <tr key={row.id}>
                    <td className="px-3 py-2 whitespace-nowrap">{fmtDate(row.createdAt)}</td>
                    <td className="px-3 py-2">{row.gareName}</td>
                    <td className="px-3 py-2">{row.cashierName ?? row.submittedByName ?? "—"}</td>
                    <td className="px-3 py-2 font-semibold">{row.amount.toLocaleString()} FCFA</td>
                    <td className="px-3 py-2">{row.caisseBalance.toLocaleString()} FCFA</td>
                    <td className="px-3 py-2">
                      <Badge variant={row.status === "en_attente" ? "outline" : "secondary"}>
                        {REVERSAL_STATUS_LABELS[row.status]}
                      </Badge>
                      {row.validatedAt ? (
                        <p className="text-[10px] text-muted-foreground mt-0.5">
                          {fmtDate(row.validatedAt)}
                          {row.accountantName ? ` · ${row.accountantName}` : ""}
                        </p>
                      ) : null}
                    </td>
                    {canValidate ? (
                      <td className="px-3 py-2">
                        {row.status === "en_attente" ? (
                          <Button
                            size="sm"
                            className="cursor-pointer"
                            disabled={actingId === row.id}
                            onClick={() => void handleValidate(row.id)}
                          >
                            <CheckIcon className="w-3.5 h-3.5 mr-1" />
                            Valider
                          </Button>
                        ) : null}
                      </td>
                    ) : null}
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
