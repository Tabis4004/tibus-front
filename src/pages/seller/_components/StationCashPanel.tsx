import { useCallback, useEffect, useState } from "react";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { LandmarkIcon, RefreshCwIcon, WalletIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getOpenStationCashSupabase,
  listCompanyStationGaresSupabase,
  listStationCashMovementsSupabase,
  openStationCashRegisterSupabase,
  submitStationCashReversalSupabase,
  STATION_CASH_MOVEMENT_LABELS,
  type OpenStationCash,
  type StationCashMovement,
  type StationGareOption,
} from "@/lib/supabase/station-cash.ts";
import { supabaseErrorMessage } from "@/lib/supabase/errors";
import { cn } from "@/lib/utils.ts";

const POLL_MS = 15_000;

function fmtDate(iso: string) {
  try {
    return format(parseISO(iso), "dd/MM/yyyy HH:mm");
  } catch {
    return iso;
  }
}

export default function StationCashPanel({
  companyId,
  canOpen = true,
}: {
  companyId: string;
  canOpen?: boolean;
}) {
  const [openingFloat, setOpeningFloat] = useState("0");
  const [gares, setGares] = useState<StationGareOption[]>([]);
  const [garesLoading, setGaresLoading] = useState(true);
  const [selectedGareId, setSelectedGareId] = useState("");
  const [cash, setCash] = useState<OpenStationCash | null | undefined>(undefined);
  const [movements, setMovements] = useState<StationCashMovement[] | undefined>(undefined);
  const [reversalAmount, setReversalAmount] = useState("");
  const [saving, setSaving] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(
    async (silent = false) => {
      if (!silent) {
        setCash(undefined);
        setMovements(undefined);
      } else {
        setRefreshing(true);
      }
      try {
        const openCash = await getOpenStationCashSupabase();
        setCash(openCash);
        if (openCash.open && openCash.id) {
          const rows = await listStationCashMovementsSupabase(openCash.id, 80);
          setMovements(rows);
          if (!reversalAmount && openCash.balance != null) {
            setReversalAmount(String(openCash.balance));
          }
        } else {
          setMovements([]);
        }
      } catch (err) {
        toast.error(supabaseErrorMessage(err, "Caisse indisponible"));
        setCash({ open: false });
        setMovements([]);
      } finally {
        setRefreshing(false);
      }
    },
    [reversalAmount],
  );

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const onRefresh = () => void load(true);
    window.addEventListener("tibus:station-cash-refresh", onRefresh);
    return () => window.removeEventListener("tibus:station-cash-refresh", onRefresh);
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => void load(true), POLL_MS);
    return () => window.clearInterval(timer);
  }, [load]);

  useEffect(() => {
    let cancelled = false;
    setGaresLoading(true);
    void listCompanyStationGaresSupabase(companyId)
      .then((rows) => {
        if (cancelled) return;
        setGares(rows);
        if (rows.length === 1) setSelectedGareId(rows[0].id);
      })
      .catch((err) => {
        if (cancelled) return;
        setGares([]);
        toast.error(supabaseErrorMessage(err, "Impossible de charger les gares"));
      })
      .finally(() => {
        if (!cancelled) setGaresLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [companyId]);

  const handleOpen = async () => {
    if (!selectedGareId) {
      toast.error("Sélectionnez la gare où vous ouvrez la caisse");
      return;
    }
    const parsed = Number(openingFloat);
    if (!Number.isFinite(parsed) || parsed < 0) {
      toast.error("Indiquez un fond de roulement valide");
      return;
    }
    setSaving(true);
    try {
      await openStationCashRegisterSupabase({
        companyId,
        gareId: selectedGareId,
        openingFloat: parsed,
      });
      toast.success("Caisse ouverte");
      await load();
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Ouverture impossible"));
    } finally {
      setSaving(false);
    }
  };

  const handleReversal = async () => {
    if (!cash?.open || !cash.id) return;
    const parsed = Number(reversalAmount);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      toast.error("Montant de reversement invalide");
      return;
    }
    setSaving(true);
    try {
      await submitStationCashReversalSupabase(cash.id, parsed);
      toast.success("Reversement soumis au comptable");
      await load(true);
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Soumission impossible"));
    } finally {
      setSaving(false);
    }
  };

  if (cash === undefined) {
    return <Skeleton className="h-40 w-full" />;
  }

  const openCash = cash ?? { open: false };

  return (
    <Card data-tour="seller-cash">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between gap-3">
          <CardTitle className="text-base flex items-center gap-2">
            <WalletIcon className="w-4 h-4" />
            Caisse physique guichet
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
      <CardContent className="space-y-4">
        <div className="rounded-lg bg-muted/40 p-3 text-xs text-muted-foreground space-y-1">
          <p><strong>1.</strong> Ouverture — choisissez votre gare et le fond de caisse du jour.</p>
          <p><strong>2.</strong> Ventes — chaque billet/colis cash crédite votre session.</p>
          <p><strong>3.</strong> Fin de service — vous soumettez le reversement vers le compte consolidé compagnie.</p>
          <p><strong>4.</strong> Validation — un comptable ou l&apos;owner approuve et clôture définitivement.</p>
        </div>

        {openCash.pendingReversal && !openCash.open ? (
          <div className="rounded-xl border border-amber-200 bg-amber-50/80 p-4 space-y-2">
            <Badge variant="secondary">En attente de validation</Badge>
            <p className="text-sm">
              Reversement de <strong>{(openCash.balance ?? 0).toLocaleString()} FCFA</strong> soumis.
              Votre session est fermée — le comptable ou l&apos;owner doit valider avant une nouvelle ouverture.
            </p>
          </div>
        ) : !openCash.open ? (
          canOpen ? (
          <div className="rounded-xl border border-dashed p-4 space-y-3">
            <p className="text-sm text-muted-foreground">
              Sélectionnez la gare où vous travaillez aujourd&apos;hui, puis indiquez le fond de roulement
              en espèces présent à l&apos;ouverture.
            </p>
            <div className="space-y-1.5 max-w-md">
              <Label>Gare du guichet *</Label>
              {garesLoading ? (
                <Skeleton className="h-9 w-full" />
              ) : gares.length ? (
                <select
                  className={cn(
                    "border-input h-9 w-full min-w-0 rounded-md border bg-transparent px-3 py-1 text-sm shadow-xs transition-[color,box-shadow] outline-none",
                    "focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]",
                    !selectedGareId && "text-muted-foreground",
                  )}
                  value={selectedGareId}
                  onChange={(event) => setSelectedGareId(event.target.value)}
                >
                  <option value="" disabled>
                    Choisir une gare
                  </option>
                  {gares.map((gare) => (
                    <option key={gare.id} value={gare.id}>
                      {gare.name}
                    </option>
                  ))}
                </select>
              ) : (
                <p className="text-xs text-amber-700 dark:text-amber-400 rounded-md border border-amber-200 bg-amber-50/80 p-2">
                  Aucune gare disponible. Ajoutez des gares dans la console owner (menu Gares).
                </p>
              )}
            </div>
            <div className="space-y-1.5 max-w-xs">
              <Label>Fond de roulement (FCFA)</Label>
              <Input
                type="number"
                min={0}
                step={1}
                value={openingFloat}
                onChange={(e) => setOpeningFloat(e.target.value)}
              />
            </div>
            <Button
              onClick={handleOpen}
              disabled={saving || garesLoading || !gares.length || !selectedGareId}
              className="cursor-pointer"
            >
              <LandmarkIcon className="w-4 h-4 mr-1.5" />
              Ouvrir la caisse du jour
            </Button>
          </div>
          ) : (
            <p className="text-sm text-muted-foreground rounded-xl border border-dashed p-4">
              L&apos;ouverture de caisse est réservée aux vendeurs. Les comptables valident les reversements
              depuis le menu Caisse compagnie.
            </p>
          )
        ) : (
          <>
            <div className="rounded-xl border bg-muted/30 p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p className="text-xs text-muted-foreground">Solde espèces actuel</p>
                  <p className="text-3xl font-black">{(openCash.balance ?? 0).toLocaleString()} FCFA</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    {openCash.sessionLabel ?? openCash.gareName ?? "Session caisse journalière"}
                    {" — "}ouverte le {openCash.openedAt ? fmtDate(openCash.openedAt) : "—"}
                  </p>
                </div>
                <Badge variant="secondary">Caisse ouverte</Badge>
              </div>
            </div>

            <div className="rounded-xl border p-4 space-y-3">
              <p className="text-sm font-semibold">Reversement fin de service</p>
              <p className="text-xs text-muted-foreground">
                Clôturez votre service : les ventes cash seront bloquées jusqu&apos;à validation par le comptable
                ou l&apos;owner sur le compte consolidé de la compagnie.
              </p>
              <div className="flex flex-wrap gap-2 items-end">
                <div className="space-y-1.5 flex-1 min-w-[180px]">
                  <Label>Montant remis (FCFA)</Label>
                  <Input
                    type="number"
                    min={1}
                    step={1}
                    value={reversalAmount}
                    onChange={(e) => setReversalAmount(e.target.value)}
                  />
                </div>
                <Button onClick={handleReversal} disabled={saving} className="cursor-pointer">
                  Soumettre au comptable
                </Button>
              </div>
            </div>
          </>
        )}

        {movements === undefined ? (
          <Skeleton className="h-32 w-full" />
        ) : movements.length > 0 ? (
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">Date</th>
                  <th className="px-3 py-2">Type</th>
                  <th className="px-3 py-2">Montant</th>
                  <th className="px-3 py-2">Solde</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {movements.map((row) => (
                  <tr key={row.id}>
                    <td className="px-3 py-2 whitespace-nowrap">{fmtDate(row.createdAt)}</td>
                    <td className="px-3 py-2">{STATION_CASH_MOVEMENT_LABELS[row.type]}</td>
                    <td className="px-3 py-2 font-medium">
                      {row.type === "decaissement_annulation" || row.type === "reversement_comptable"
                        ? "−"
                        : "+"}
                      {row.amount.toLocaleString()}
                    </td>
                    <td className="px-3 py-2">{row.balanceAfter.toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : openCash.open ? (
          <p className="text-sm text-muted-foreground">Aucun mouvement pour cette session.</p>
        ) : null}
      </CardContent>
    </Card>
  );
}
