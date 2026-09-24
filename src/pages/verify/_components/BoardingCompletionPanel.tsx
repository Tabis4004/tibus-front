import { useEffect, useState } from "react";
import { toast } from "sonner";
import { AlertTriangleIcon, CheckCircle2Icon } from "lucide-react";
import { errorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
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
import {
  declareGareBoardingDone,
  listGareCompletions,
  type GareCompletion,
  type WrongRoutePassenger,
} from "@/lib/supabase/embarquement-completion";

const REASON_LABEL: Record<string, string> = {
  autre_depart: "Billet d'un autre départ",
  autre_gare: "Billet ne partant pas de cette gare",
};

/**
 * À placer sur l'écran de session d'embarquement.
 * L'embarqueur saisit le nombre total de passagers embarqués dans sa gare et
 * valide. La session n'est pas fermée (plusieurs gares/escales sur le trajet).
 * Si des passagers scannés sont dans le mauvais car, une alerte les liste et
 * l'embarqueur doit confirmer avant l'enregistrement.
 */
export default function BoardingCompletionPanel({
  sessionId,
  suggestedCount,
  onDone,
}: {
  sessionId: string;
  suggestedCount?: number;
  onDone?: () => void;
}) {
  const [count, setCount] = useState(suggestedCount != null ? String(suggestedCount) : "");
  const [saving, setSaving] = useState(false);
  const [wrong, setWrong] = useState<WrongRoutePassenger[] | null>(null);
  const [history, setHistory] = useState<GareCompletion[]>([]);

  const reload = async () => {
    try {
      setHistory(await listGareCompletions(sessionId));
    } catch {
      /* historique non bloquant */
    }
  };

  useEffect(() => {
    void reload();
  }, [sessionId]);

  const submit = async (ackWrong: boolean) => {
    const n = Number(count);
    if (!Number.isInteger(n) || n < 0) {
      toast.error("Saisissez le nombre total de passagers embarqués");
      return;
    }
    setSaving(true);
    try {
      const res = await declareGareBoardingDone({ sessionId, passengerCount: n, ackWrong });
      if (!res.ok && res.needs_ack) {
        setWrong(res.wrong_route);
        return;
      }
      setWrong(null);
      toast.success(
        res.count_mismatch
          ? `Embarquement déclaré (${res.declared_count} saisis, ${res.scanned_count} scannés)`
          : "Fin d'embarquement déclarée",
      );
      await reload();
      onDone?.();
    } catch (err) {
      toast.error(errorMessage(err, "Impossible de déclarer la fin d'embarquement"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-3 rounded-xl border p-4">
      <div className="space-y-1.5">
        <Label htmlFor="boarding-count">Nombre total de passagers embarqués</Label>
        <Input
          id="boarding-count"
          type="number"
          min={0}
          value={count}
          onChange={(e) => setCount(e.target.value)}
        />
      </div>
      <Button className="w-full" disabled={saving || count === ""} onClick={() => void submit(false)}>
        <CheckCircle2Icon className="w-4 h-4 mr-1.5" />
        J'ai fini d'embarquer dans ma gare
      </Button>
      <p className="text-[11px] text-muted-foreground">
        La session reste ouverte pour les autres gares du trajet.
      </p>

      {history.length > 0 && (
        <ul className="text-xs space-y-1 pt-1 border-t">
          {history.map((h) => (
            <li key={h.id} className="flex justify-between gap-2">
              <span>{h.gare_name ?? "Gare"}</span>
              <span className="text-muted-foreground">
                {h.declared_count} embarqués
                {h.wrong_route_count > 0 ? ` · ${h.wrong_route_count} mauvais car` : ""}
              </span>
            </li>
          ))}
        </ul>
      )}

      <AlertDialog open={wrong !== null} onOpenChange={(o) => !o && setWrong(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              <AlertTriangleIcon className="w-5 h-5 text-destructive" />
              Passagers dans le mauvais car
            </AlertDialogTitle>
            <AlertDialogDescription>
              Ces passagers ne sont pas sur cet itinéraire. Ils doivent descendre à l'escale
              et attendre leur départ.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <ul className="max-h-60 overflow-y-auto space-y-2 text-sm">
            {(wrong ?? []).map((w) => (
              <li key={w.scan_id} className="rounded-lg border p-2">
                <div className="font-semibold">{w.passenger_name ?? "Passager"}</div>
                <div className="text-xs text-muted-foreground">
                  {w.ticket_number} · {w.ticket_from ?? "?"} → {w.ticket_to ?? "?"}
                </div>
                {w.reason && (
                  <div className="text-xs text-destructive">{REASON_LABEL[w.reason]}</div>
                )}
              </li>
            ))}
          </ul>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={saving}>Corriger d'abord</AlertDialogCancel>
            <AlertDialogAction disabled={saving} onClick={() => void submit(true)}>
              Passagers informés, valider
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
