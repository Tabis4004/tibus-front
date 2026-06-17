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
  listStationCashMovementsSupabase,
  openStationCashRegisterSupabase,
  submitStationCashReversalSupabase,
  STATION_CASH_MOVEMENT_LABELS,
  type OpenStationCash,
  type StationCashMovement,
} from "@/lib/supabase/station-cash.ts";
import { supabaseErrorMessage } from "@/lib/supabase/errors";

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

  const handleOpen = async () => {
    const parsed = Number(openingFloat);
    if (!Number.isFinite(parsed) || parsed < 0) {
      toast.error("Indiquez un fond de roulement valide");
      return;
    }
    setSaving(true);
    try {
      await openStationCashRegisterSupabase({
        companyId,
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
          <p><strong>1.</strong> Ouverture — vous démarrez avec un fond en caisse (session du jour).</p>
          <p><strong>2.</strong> Ventes — chaque billet/colis cash crédite votre session (tous trajets).</p>
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
              Indiquez le fond de roulement en espèces présent à l&apos;ouverture. Aucun trajet à choisir :
              la session couvre toutes vos ventes cash de la journée.
            </p>
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
            <Button onClick={handleOpen} disabled={saving} className="cursor-pointer">
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
