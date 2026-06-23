// src/pages/admin/_components/PayAtStationPanel.tsx
// Panel superadmin pour :
//   1. Activer/désactiver "Payer en gare" par compagnie
//   2. Éditer le message affiché sur le reçu de réservation

import { useEffect, useState } from "react";
import { MapPinIcon, PencilIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import {
  getPayAtStationConfigSupabase,
  setPayAtStationConfigSupabase,
  getPayAtStationReceiptMsgSupabase,
  upsertPayAtStationReceiptMsgSupabase,
  DEFAULT_STATION_RECEIPT_MSG,
  type PayAtStationReceiptMsg,
} from "@/lib/supabase/pay-at-station.ts";

type Props = {
  companyId: string;
  companyName?: string;
  readOnly?: boolean;
  /** Si true, affiche aussi l'éditeur du message reçu (superadmin uniquement) */
  showMsgEditor?: boolean;
};

export default function PayAtStationPanel({
  companyId,
  companyName,
  readOnly = false,
  showMsgEditor = false,
}: Props) {
  // ── Toggle compagnie ──
  const [loading, setLoading]   = useState(true);
  const [saving, setSaving]     = useState(false);
  const [enabled, setEnabled]   = useState(false);
  const [original, setOriginal] = useState(false);

  // ── Message reçu ──
  const [msgLoading, setMsgLoading]   = useState(false);
  const [msgSaving, setMsgSaving]     = useState(false);
  const [msg, setMsg]                 = useState<PayAtStationReceiptMsg>(DEFAULT_STATION_RECEIPT_MSG);
  const [originalMsg, setOriginalMsg] = useState<PayAtStationReceiptMsg>(DEFAULT_STATION_RECEIPT_MSG);

  // ── Charger config compagnie ──
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    getPayAtStationConfigSupabase(companyId)
      .then((cfg) => {
        if (cancelled) return;
        setEnabled(cfg.payAtStation);
        setOriginal(cfg.payAtStation);
      })
      .catch(() => toast.error("Impossible de charger la config payer en gare."))
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [companyId]);

  // ── Charger message reçu ──
  useEffect(() => {
    if (!showMsgEditor) return;
    let cancelled = false;
    setMsgLoading(true);
    getPayAtStationReceiptMsgSupabase()
      .then((m) => {
        if (cancelled) return;
        setMsg(m);
        setOriginalMsg(m);
      })
      .catch(() => {/* silencieux, on garde le défaut */})
      .finally(() => { if (!cancelled) setMsgLoading(false); });
    return () => { cancelled = true; };
  }, [showMsgEditor]);

  const isDirty    = enabled !== original;
  const isMsgDirty = msg.title !== originalMsg.title || msg.line1 !== originalMsg.line1 || msg.line2 !== originalMsg.line2;

  const handleSaveToggle = async () => {
    setSaving(true);
    try {
      await setPayAtStationConfigSupabase(companyId, enabled);
      setOriginal(enabled);
      toast.success(
        enabled
          ? `"Payer en gare" activé${companyName ? ` pour ${companyName}` : ""}.`
          : `"Payer en gare" désactivé.`,
      );
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Erreur d'enregistrement.");
    } finally {
      setSaving(false);
    }
  };

  const handleSaveMsg = async () => {
    setMsgSaving(true);
    try {
      await upsertPayAtStationReceiptMsgSupabase(msg);
      setOriginalMsg(msg);
      toast.success("Message du reçu mis à jour.");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Erreur d'enregistrement.");
    } finally {
      setMsgSaving(false);
    }
  };

  if (loading) return <Skeleton className="h-40 w-full rounded-xl" />;

  return (
    <div className="space-y-4">
      {/* ── Toggle par compagnie ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <MapPinIcon className="w-4 h-4" />
            Payer en gare
            {original && (
              <Badge variant="secondary" className="text-[11px] ml-1">Actif</Badge>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-5">
          <p className="text-sm text-muted-foreground leading-relaxed">
            Quand cette option est activée, le voyageur paie en ligne uniquement les{" "}
            <strong>frais plateforme (X%)</strong> et les <strong>frais gateway (Y+Z+F)</strong>{" "}
            définis par la plateforme. Le montant billet <strong>M</strong> est réglé en gare de
            départ. Un reçu de réservation est émis à la place d'un ticket acquitté.
          </p>

          <div className="flex items-center justify-between rounded-lg border px-4 py-3">
            <div className="space-y-0.5">
              <Label className="text-sm font-medium cursor-pointer">
                Activer pour cette compagnie
              </Label>
              <p className="text-xs text-muted-foreground">
                {enabled
                  ? "Le voyageur paie les frais en ligne — M en gare."
                  : "Paiement complet en ligne (comportement par défaut)."}
              </p>
            </div>
            <Switch
              checked={enabled}
              disabled={readOnly || saving}
              onCheckedChange={setEnabled}
              aria-label="Activer payer en gare"
            />
          </div>

          {enabled && (
            <div className="rounded-md border bg-amber-50 dark:bg-amber-950/30 border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300 space-y-1">
              <p className="font-semibold">Aperçu de la mention sur le reçu :</p>
              <p className="italic">« {msg.title} — {msg.line1} »</p>
            </div>
          )}

          {!readOnly && isDirty && (
            <Button
              onClick={() => void handleSaveToggle()}
              disabled={saving}
              className="w-full"
            >
              {saving ? "Enregistrement…" : "Enregistrer"}
            </Button>
          )}
        </CardContent>
      </Card>

      {/* ── Éditeur du message reçu (superadmin uniquement) ── */}
      {showMsgEditor && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <PencilIcon className="w-4 h-4" />
              Message du reçu de réservation
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Ce message apparaît sur tous les reçus de réservation "Payer en gare",
              quelle que soit la compagnie.
            </p>

            {msgLoading ? (
              <Skeleton className="h-24 w-full" />
            ) : (
              <div className="space-y-3">
                <div className="space-y-1.5">
                  <Label className="text-xs">Titre</Label>
                  <Input
                    value={msg.title}
                    onChange={(e) => setMsg((m) => ({ ...m, title: e.target.value }))}
                    placeholder={DEFAULT_STATION_RECEIPT_MSG.title}
                    disabled={msgSaving}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs">Ligne principale</Label>
                  <Textarea
                    value={msg.line1}
                    onChange={(e) => setMsg((m) => ({ ...m, line1: e.target.value }))}
                    placeholder={DEFAULT_STATION_RECEIPT_MSG.line1}
                    rows={2}
                    disabled={msgSaving}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs">Préfixe montant dû</Label>
                  <Input
                    value={msg.line2}
                    onChange={(e) => setMsg((m) => ({ ...m, line2: e.target.value }))}
                    placeholder={DEFAULT_STATION_RECEIPT_MSG.line2}
                    disabled={msgSaving}
                  />
                </div>

                {/* Aperçu */}
                <div className="rounded-md border bg-amber-50 dark:bg-amber-950/30 border-amber-200 dark:border-amber-800 p-3 text-xs space-y-1">
                  <p className="font-semibold text-amber-800 dark:text-amber-300">Aperçu PDF :</p>
                  <p className="font-bold text-amber-800 dark:text-amber-300">⚠ {msg.title}</p>
                  <p className="text-amber-700 dark:text-amber-400">{msg.line1}</p>
                  <p className="text-amber-700 dark:text-amber-400">{msg.line2} XOF 5 000</p>
                </div>

                {isMsgDirty && (
                  <Button
                    onClick={() => void handleSaveMsg()}
                    disabled={msgSaving}
                    className="w-full"
                  >
                    {msgSaving ? "Enregistrement…" : "Enregistrer le message"}
                  </Button>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
