// src/pages/admin/_components/PayAtStationPanel.tsx
// Panel admin pour configurer l'option "Payer en gare" par compagnie.
// À insérer dans la page admin compagnie (même endroit que CompanyFeatureModulesPanel).

import { useEffect, useState } from "react";
import { MapPinIcon, InfoIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  getPayAtStationConfigSupabase,
  setPayAtStationConfigSupabase,
  type PayAtStationConfig,
  type PayAtStationFeeType,
} from "@/lib/supabase/pay-at-station.ts";

type Props = {
  companyId: string;
  companyCurrency?: string;   // ex: "XOF", "XAF"
  readOnly?: boolean;
};

export default function PayAtStationPanel({
  companyId,
  companyCurrency = "XOF",
  readOnly = false,
}: Props) {
  const [config, setConfig] = useState<PayAtStationConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving]   = useState(false);

  // Champs locaux du formulaire
  const [enabled,  setEnabled]  = useState(false);
  const [feeType,  setFeeType]  = useState<PayAtStationFeeType>("percent");
  const [feeValue, setFeeValue] = useState("");

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    getPayAtStationConfigSupabase(companyId)
      .then((cfg) => {
        if (cancelled) return;
        setConfig(cfg);
        setEnabled(cfg.payAtStation);
        setFeeType(cfg.payAtStationFeeType);
        setFeeValue(cfg.payAtStationFeeValue > 0 ? String(cfg.payAtStationFeeValue) : "");
      })
      .catch(() => {
        if (!cancelled) setConfig(null);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }, [companyId]);

  const isDirty =
    config !== null && (
      enabled  !== config.payAtStation ||
      feeType  !== config.payAtStationFeeType ||
      feeValue !== (config.payAtStationFeeValue > 0 ? String(config.payAtStationFeeValue) : "")
    );

  const handleSave = async () => {
    const parsedValue = parseFloat(feeValue.replace(",", "."));
    if (isNaN(parsedValue) || parsedValue < 0) {
      toast.error("Valeur des frais invalide.");
      return;
    }
    if (feeType === "percent" && parsedValue > 100) {
      toast.error("Le pourcentage ne peut pas dépasser 100 %.");
      return;
    }
    setSaving(true);
    try {
      const next: PayAtStationConfig = {
        payAtStation:        enabled,
        payAtStationFeeType: feeType,
        payAtStationFeeValue: parsedValue,
      };
      await setPayAtStationConfigSupabase(companyId, next);
      setConfig(next);
      toast.success("Option \"Payer en gare\" mise à jour.");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Enregistrement impossible.");
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <Skeleton className="h-48 w-full rounded-xl" />;

  if (!config) {
    return (
      <Card>
        <CardContent className="pt-6 text-sm text-muted-foreground">
          Configuration indisponible. Vérifiez que la migration SQL 103 est exécutée.
        </CardContent>
      </Card>
    );
  }

  // Aperçu du calcul pour l'admin
  const previewExample = () => {
    const M = 5000;
    const val = parseFloat(feeValue.replace(",", "."));
    if (isNaN(val) || val <= 0) return null;
    const x = feeType === "percent" ? Math.round(M * val / 100) : val;
    return { M, x };
  };
  const preview = previewExample();

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base flex items-center gap-2">
          <MapPinIcon className="w-4 h-4" />
          Option "Payer en gare"
          {config.payAtStation && (
            <Badge variant="secondary" className="text-[11px] ml-1">Actif</Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-5">

        {/* Description */}
        <p className="text-sm text-muted-foreground">
          Quand cette option est activée, le voyageur ne paie en ligne que
          les <strong>frais de service (X)</strong> et les <strong>frais gateway (Y+Z+F)</strong>.
          Le montant billet <strong>M</strong> est réglé directement en gare de départ.
          Un reçu de réservation est émis à la place d'un ticket payé.
        </p>

        {/* Toggle principal */}
        <div className="flex items-center justify-between rounded-lg border px-4 py-3">
          <div className="space-y-1">
            <Label className="text-sm font-medium">Activer pour cette compagnie</Label>
            <p className="text-xs text-muted-foreground">
              Le voyageur paie uniquement les frais en ligne.
            </p>
          </div>
          <Switch
            checked={enabled}
            disabled={readOnly || saving}
            onCheckedChange={setEnabled}
            aria-label="Activer payer en gare"
          />
        </div>

        {/* Config des frais (visible seulement si activé) */}
        {enabled && (
          <div className="space-y-4 rounded-lg border border-dashed bg-muted/20 p-4">

            <div className="grid grid-cols-2 gap-4">
              {/* Type de frais X */}
              <div className="space-y-2">
                <Label className="text-sm">Type des frais plateforme (X)</Label>
                <Select
                  value={feeType}
                  onValueChange={(v) => setFeeType(v as PayAtStationFeeType)}
                  disabled={readOnly || saving}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="percent">Pourcentage du billet (%)</SelectItem>
                    <SelectItem value="fixed">Montant fixe ({companyCurrency})</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {/* Valeur de X */}
              <div className="space-y-2">
                <Label className="text-sm">
                  Valeur X{feeType === "percent" ? " (%)" : ` (${companyCurrency})`}
                </Label>
                <Input
                  type="number"
                  min="0"
                  max={feeType === "percent" ? "100" : undefined}
                  step="0.5"
                  placeholder={feeType === "percent" ? "ex: 2.5" : "ex: 200"}
                  value={feeValue}
                  onChange={(e) => setFeeValue(e.target.value)}
                  disabled={readOnly || saving}
                />
              </div>
            </div>

            {/* Aperçu calculé */}
            {preview && (
              <div className="rounded-md bg-blue-50 dark:bg-blue-950/30 border border-blue-200 dark:border-blue-800 p-3 text-xs space-y-1">
                <div className="flex items-center gap-1 font-medium text-blue-800 dark:text-blue-200">
                  <InfoIcon className="w-3 h-3" />
                  Aperçu pour un billet à {preview.M.toLocaleString()} {companyCurrency}
                </div>
                <div className="text-blue-700 dark:text-blue-300 space-y-0.5">
                  <p>• Montant billet M = <strong>{preview.M.toLocaleString()} {companyCurrency}</strong> → payé en gare</p>
                  <p>• Frais plateforme X = <strong>{preview.x.toLocaleString()} {companyCurrency}</strong></p>
                  <p className="opacity-70">+ frais gateway Y/Z/F calculés selon réseau mobile</p>
                  <p className="mt-1 font-medium">
                    → Le voyageur paie en ligne : X + Y + Z + F (les frais uniquement)
                  </p>
                </div>
              </div>
            )}

            {/* Mention ticket */}
            <div className="rounded-md border bg-amber-50 dark:bg-amber-950/30 border-amber-200 dark:border-amber-800 p-3 text-xs text-amber-800 dark:text-amber-300">
              <strong>Mention sur le reçu :</strong>
              <br />
              « Ceci est un reçu de réservation. Le montant dû à la compagnie
              est à régler en gare de départ. »
            </div>
          </div>
        )}

        {/* Bouton save */}
        {!readOnly && isDirty && (
          <Button
            onClick={() => void handleSave()}
            disabled={saving}
            className="w-full"
          >
            {saving ? "Enregistrement…" : "Enregistrer"}
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
