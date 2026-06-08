import { useCallback, useEffect, useState } from "react";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { ChevronDownIcon, ChevronUpIcon, RefreshCwIcon, WalletIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  listCompanyOpenStationCashSupabase,
  listStationCashMovementsSupabase,
  STATION_CASH_MOVEMENT_LABELS,
  type CompanyOpenStationCash,
  type StationCashMovement,
} from "@/lib/supabase/station-cash.ts";

const POLL_MS = 20_000;

function fmtDate(iso: string) {
  try {
    return format(parseISO(iso), "dd/MM/yyyy HH:mm");
  } catch {
    return iso;
  }
}

export default function StationCashOverviewPanel({ companyId }: { companyId: string }) {
  const [rows, setRows] = useState<CompanyOpenStationCash[] | undefined>(undefined);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [movements, setMovements] = useState<Record<string, StationCashMovement[] | undefined>>({});
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(
    async (silent = false) => {
      if (!silent) setRows(undefined);
      else setRefreshing(true);
      try {
        const data = await listCompanyOpenStationCashSupabase(companyId);
        setRows(data);
        if (expandedId && !data.some((row) => row.id === expandedId)) {
          setExpandedId(null);
        }
      } catch (err) {
        toast.error(err instanceof Error ? err.message : "Chargement impossible");
        setRows([]);
      } finally {
        setRefreshing(false);
      }
    },
    [companyId, expandedId],
  );

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => void load(true), POLL_MS);
    return () => window.clearInterval(timer);
  }, [load]);

  const toggleMovements = async (caisseId: string) => {
    if (expandedId === caisseId) {
      setExpandedId(null);
      return;
    }
    setExpandedId(caisseId);
    if (movements[caisseId]) return;
    setMovements((prev) => ({ ...prev, [caisseId]: undefined }));
    try {
      const rows = await listStationCashMovementsSupabase(caisseId, 50);
      setMovements((prev) => ({ ...prev, [caisseId]: rows }));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Mouvements indisponibles");
      setMovements((prev) => ({ ...prev, [caisseId]: [] }));
    }
  };

  const totalBalance = rows?.reduce((sum, row) => sum + row.balance, 0) ?? 0;

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <CardTitle className="text-base flex items-center gap-2">
            <WalletIcon className="w-4 h-4" />
            Caisses ouvertes
            {rows && rows.length > 0 ? (
              <Badge variant="secondary">
                {totalBalance.toLocaleString()} FCFA au total
              </Badge>
            ) : null}
          </CardTitle>
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
      </CardHeader>
      <CardContent>
        {rows === undefined ? (
          <Skeleton className="h-32 w-full" />
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucune caisse ouverte pour le moment.</p>
        ) : (
          <div className="space-y-3">
            {rows.map((row) => {
              const expanded = expandedId === row.id;
              const caisseMovements = movements[row.id];
              return (
                <div key={row.id} className="rounded-xl border overflow-hidden">
                  <div className="p-4 flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <p className="font-semibold">{row.gareName}</p>
                      <p className="text-xs text-muted-foreground">
                        {row.cashierName ?? "Guichetier"} — ouverte le {fmtDate(row.openedAt)}
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-xl font-black">{row.balance.toLocaleString()} FCFA</p>
                      <p className="text-[10px] text-muted-foreground">
                        Fond {row.openingFloat.toLocaleString()} FCFA
                      </p>
                    </div>
                  </div>
                  <div className="px-4 pb-4">
                    <Button
                      size="sm"
                      variant="ghost"
                      className="cursor-pointer h-8 px-2"
                      onClick={() => void toggleMovements(row.id)}
                    >
                      {expanded ? (
                        <ChevronUpIcon className="w-4 h-4 mr-1" />
                      ) : (
                        <ChevronDownIcon className="w-4 h-4 mr-1" />
                      )}
                      Journal des mouvements
                    </Button>
                  </div>
                  {expanded ? (
                    <div className="border-t bg-muted/20 px-4 py-3">
                      {caisseMovements === undefined ? (
                        <Skeleton className="h-20 w-full" />
                      ) : caisseMovements.length === 0 ? (
                        <p className="text-xs text-muted-foreground">Aucun mouvement.</p>
                      ) : (
                        <div className="overflow-x-auto">
                          <table className="min-w-full text-xs">
                            <thead>
                              <tr className="text-left text-muted-foreground">
                                <th className="py-1 pr-3">Date</th>
                                <th className="py-1 pr-3">Type</th>
                                <th className="py-1 pr-3">Montant</th>
                                <th className="py-1">Solde</th>
                              </tr>
                            </thead>
                            <tbody>
                              {caisseMovements.map((movement) => (
                                <tr key={movement.id}>
                                  <td className="py-1 pr-3 whitespace-nowrap">
                                    {fmtDate(movement.createdAt)}
                                  </td>
                                  <td className="py-1 pr-3">
                                    {STATION_CASH_MOVEMENT_LABELS[movement.type]}
                                  </td>
                                  <td className="py-1 pr-3 font-medium">
                                    {movement.type === "decaissement_annulation" ||
                                    movement.type === "reversement_comptable"
                                      ? "−"
                                      : "+"}
                                    {movement.amount.toLocaleString()}
                                  </td>
                                  <td className="py-1">{movement.balanceAfter.toLocaleString()}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      )}
                    </div>
                  ) : null}
                </div>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
