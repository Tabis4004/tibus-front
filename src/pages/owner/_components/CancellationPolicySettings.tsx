import { useEffect, useState } from "react";
import { toast } from "sonner";
import { PlusIcon, SaveIcon, TrashIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  getCompanyCancellationPolicySupabase,
  upsertCompanyCancellationPolicySupabase,
  type CancellationPenaltyTier,
  type CompanyCancellationConfig,
  type PenaltyType,
} from "@/lib/supabase/cancellation.ts";

function emptyTier(index: number): CancellationPenaltyTier {
  return {
    label: "",
    minHoursBeforeDeparture: 72,
    penaltyType: "percent",
    penaltyValue: 0,
    sortOrder: index,
  };
}

export default function CancellationPolicySettings({ companyId }: { companyId: string }) {
  const [config, setConfig] = useState<CompanyCancellationConfig | undefined>(undefined);
  const [saving, setSaving] = useState(false);

  const load = () => {
    setConfig(undefined);
    void getCompanyCancellationPolicySupabase(companyId)
      .then(setConfig)
      .catch((err) => toast.error(err instanceof Error ? err.message : "Chargement impossible"));
  };

  useEffect(() => {
    load();
  }, [companyId]);

  const updatePolicy = <K extends keyof CompanyCancellationConfig["policy"]>(
    key: K,
    value: CompanyCancellationConfig["policy"][K],
  ) => {
    setConfig((prev) =>
      prev ? { ...prev, policy: { ...prev.policy, [key]: value } } : prev,
    );
  };

  const updateTier = (index: number, patch: Partial<CancellationPenaltyTier>) => {
    setConfig((prev) => {
      if (!prev) return prev;
      const tiers = [...prev.tiers];
      tiers[index] = { ...tiers[index], ...patch };
      return { ...prev, tiers };
    });
  };

  const addTier = () => {
    setConfig((prev) =>
      prev ? { ...prev, tiers: [...prev.tiers, emptyTier(prev.tiers.length)] } : prev,
    );
  };

  const removeTier = (index: number) => {
    setConfig((prev) => {
      if (!prev) return prev;
      return { ...prev, tiers: prev.tiers.filter((_, i) => i !== index) };
    });
  };

  const handleSave = async () => {
    if (!config) return;
    setSaving(true);
    try {
      const saved = await upsertCompanyCancellationPolicySupabase(companyId, {
        ...config,
        tiers: config.tiers
          .slice()
          .sort((a, b) => b.minHoursBeforeDeparture - a.minHoursBeforeDeparture)
          .map((tier, index) => ({ ...tier, sortOrder: index })),
      });
      setConfig(saved);
      toast.success("Politique d'annulation enregistrée");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Enregistrement impossible");
    } finally {
      setSaving(false);
    }
  };

  if (config === undefined) {
    return <Skeleton className="h-64 w-full" />;
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-bold">Pénalités d&apos;annulation</h2>
        <p className="text-sm text-muted-foreground">
          Remboursement = M encaissé − P pénalité. En dessous du délai critique, seuls owner et
          vendeur peuvent annuler.
        </p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Paramètres généraux</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <Label>Politique active</Label>
              <p className="text-xs text-muted-foreground">
                Désactivée = annulation sans pénalité (0 %).
              </p>
            </div>
            <Switch
              checked={config.policy.isActive}
              onCheckedChange={(checked) => updatePolicy("isActive", checked)}
            />
          </div>

          <div className="grid gap-4 md:grid-cols-3">
            <div className="space-y-1.5">
              <Label>Délai critique (heures avant départ)</Label>
              <Input
                type="number"
                min={0}
                step={1}
                value={config.policy.criticalHoursBeforeDeparture}
                onChange={(e) =>
                  updatePolicy("criticalHoursBeforeDeparture", Number(e.target.value) || 0)
                }
              />
              <p className="text-[11px] text-muted-foreground">
                Sous ce seuil : annulation réservée au staff (owner/vendeur).
              </p>
            </div>
            <div className="space-y-1.5">
              <Label>Type pénalité critique</Label>
              <Select
                value={config.policy.criticalPenaltyType}
                onValueChange={(value) =>
                  updatePolicy("criticalPenaltyType", value as PenaltyType)
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="percent">Pourcentage (%)</SelectItem>
                  <SelectItem value="fixed">Montant fixe</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>
                Valeur critique{" "}
                {config.policy.criticalPenaltyType === "percent" ? "(%)" : "(fixe)"}
              </Label>
              <Input
                type="number"
                min={0}
                step={config.policy.criticalPenaltyType === "percent" ? 1 : 100}
                value={config.policy.criticalPenaltyValue}
                onChange={(e) =>
                  updatePolicy("criticalPenaltyValue", Number(e.target.value) || 0)
                }
              />
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3 flex flex-row items-center justify-between gap-3">
          <div>
            <CardTitle className="text-base">Paliers par période</CardTitle>
            <p className="text-xs text-muted-foreground mt-1">
              Plus le départ est proche, plus le palier avec le plus grand seuil d&apos;heures
              s&apos;applique.
            </p>
          </div>
          <Button variant="outline" size="sm" onClick={addTier}>
            <PlusIcon className="w-4 h-4 mr-1" />
            Palier
          </Button>
        </CardHeader>
        <CardContent className="space-y-3">
          {config.tiers.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Aucun palier : hors zone critique, annulation sans pénalité.
            </p>
          ) : (
            config.tiers.map((tier, index) => (
              <div
                key={tier.id ?? `tier-${index}`}
                className="grid gap-3 rounded-lg border p-3 md:grid-cols-[1fr_1fr_1fr_1fr_auto]"
              >
                <div className="space-y-1">
                  <Label className="text-xs">Libellé</Label>
                  <Input
                    placeholder="ex. 72h+"
                    value={tier.label ?? ""}
                    onChange={(e) => updateTier(index, { label: e.target.value })}
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Min. heures avant départ</Label>
                  <Input
                    type="number"
                    min={0}
                    value={tier.minHoursBeforeDeparture}
                    onChange={(e) =>
                      updateTier(index, {
                        minHoursBeforeDeparture: Number(e.target.value) || 0,
                      })
                    }
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Type</Label>
                  <Select
                    value={tier.penaltyType}
                    onValueChange={(value) =>
                      updateTier(index, { penaltyType: value as PenaltyType })
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="percent">%</SelectItem>
                      <SelectItem value="fixed">Fixe</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Valeur</Label>
                  <Input
                    type="number"
                    min={0}
                    value={tier.penaltyValue}
                    onChange={(e) =>
                      updateTier(index, { penaltyValue: Number(e.target.value) || 0 })
                    }
                  />
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  className="self-end"
                  onClick={() => removeTier(index)}
                >
                  <TrashIcon className="w-4 h-4 text-destructive" />
                </Button>
              </div>
            ))
          )}
        </CardContent>
      </Card>

      <Button onClick={handleSave} disabled={saving}>
        <SaveIcon className="w-4 h-4 mr-1.5" />
        {saving ? "Enregistrement…" : "Enregistrer la politique"}
      </Button>
    </div>
  );
}
