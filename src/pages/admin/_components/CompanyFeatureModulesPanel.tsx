import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { LayersIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { COMMERCIAL_MODULE_LABELS } from "@/lib/company-feature-module-map.ts";
import type {
  CompanyFeatureModuleId,
  CompanyFeatureModules,
} from "@/lib/company-feature-modules.ts";
import {
  getCompanyFeatureModulesSupabase,
  setCompanyFeatureModulesSupabase,
  setCompanyColisSmsStepsAllowedSupabase,
} from "@/lib/supabase/company-feature-modules.ts";
import { cn } from "@/lib/utils.ts";
import { commercialModuleTileIndex, consoleTileStyle } from "@/lib/console-grid-tiles.ts";

const MODULE_ORDER: CompanyFeatureModuleId[] = ["A", "B", "C", "D", "E", "F"];

type Props = {
  companyId: string;
  readOnly?: boolean;
};

export default function CompanyFeatureModulesPanel({ companyId, readOnly = false }: Props) {
  const { t } = useTranslation("admin");
  const [modules, setModules] = useState<CompanyFeatureModules | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    void getCompanyFeatureModulesSupabase(companyId)
      .then((row) => {
        if (!cancelled) setModules(row);
      })
      .catch(() => {
        if (!cancelled) setModules(null);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [companyId]);

  const persist = async (draft: CompanyFeatureModules) => {
    setSaving(true);
    try {
      const saved = await setCompanyFeatureModulesSupabase(companyId, {
        moduleA: draft.moduleA,
        moduleB: draft.moduleB,
        moduleC: draft.moduleC,
        moduleD: draft.moduleD,
        moduleE: draft.moduleE,
        moduleF: draft.moduleF,
        moduleDColisSmsConfig: draft.moduleDColisSmsConfig,
      });
      setModules(saved);
      toast.success(t("feature_modules.saved", { defaultValue: "Modules mis à jour." }));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Enregistrement impossible.");
    } finally {
      setSaving(false);
    }
  };

  const toggle = async (key: keyof Pick<
    CompanyFeatureModules,
    "moduleA" | "moduleB" | "moduleC" | "moduleD" | "moduleE" | "moduleF"
  >, next: boolean) => {
    if (!modules || readOnly) return;
    const draft = { ...modules, [key]: next };
    if (key === "moduleA" && !next) {
      draft.moduleB = false;
      draft.moduleC = false;
      draft.moduleE = false;
    }
    if (key === "moduleD" && !next) {
      draft.moduleDColisSmsConfig = false;
    }
    if ((key === "moduleB" || key === "moduleC" || key === "moduleE") && next && !draft.moduleA) {
      toast.error(
        t("feature_modules.requires_a", {
          defaultValue: "Le module A (billetterie) doit être activé en premier.",
        }),
      );
      return;
    }
    await persist(draft);
  };

  // Étapes SMS colis incluses dans l'offre : le super admin choisit
  // précisément ce que l'owner pourra activer (facturation à l'étape).
  const toggleSmsStep = async (
    step: "enregistre" | "charge" | "arrive" | "livre",
    next: boolean,
  ) => {
    if (!modules || readOnly || !modules.moduleD) return;
    const steps = {
      enregistre: modules.smsEnregistreAllowed,
      charge: modules.smsChargeAllowed,
      arrive: modules.smsArriveAllowed,
      livre: modules.smsLivreAllowed,
      [step]: next,
    };
    setSaving(true);
    try {
      const saved = await setCompanyColisSmsStepsAllowedSupabase(companyId, steps);
      setModules(saved);
      toast.success(
        t("feature_modules.sms_steps_saved", {
          defaultValue: "Étapes SMS colis mises à jour.",
        }),
      );
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Enregistrement impossible.");
    } finally {
      setSaving(false);
    }
  };

  const flagKey = (
    id: CompanyFeatureModuleId,
  ): "moduleA" | "moduleB" | "moduleC" | "moduleD" | "moduleE" | "moduleF" => {
    const map = {
      A: "moduleA",
      B: "moduleB",
      C: "moduleC",
      D: "moduleD",
      E: "moduleE",
      F: "moduleF",
    } as const;
    return map[id];
  };

  if (loading) {
    return <Skeleton className="h-64 w-full rounded-xl" />;
  }

  if (!modules) {
    return (
      <Card>
        <CardContent className="pt-6 text-sm text-muted-foreground">
          {t("feature_modules.load_error", {
            defaultValue: "Modules indisponibles (migration SQL 120 requise).",
          })}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base flex items-center gap-2">
          <LayersIcon className="w-4 h-4" />
          {t("feature_modules.title", { defaultValue: "Modules commerciaux" })}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          {t("feature_modules.desc", {
            defaultValue:
              "Activez les blocs A–F de l'offre commerciale Tibus pour cette compagnie. Les prérequis B, C et E imposent le module A.",
          })}
        </p>
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          {MODULE_ORDER.map((id) => {
            const meta = COMMERCIAL_MODULE_LABELS[id];
            const key = flagKey(id);
            const enabled = Boolean(modules[key]);
            const needsA = (id === "B" || id === "C" || id === "E") && !modules.moduleA;
            const tile = consoleTileStyle(commercialModuleTileIndex(id));

            return (
              <div key={id} className="space-y-2">
                <div
                  className={cn(
                    "flex h-full min-h-[128px] flex-col items-center justify-between gap-3 rounded-2xl border p-4 text-center",
                    tile.tile,
                    tile.border,
                  )}
                >
                  <div className="space-y-2 min-w-0 w-full">
                    <div className={cn("w-10 h-10 mx-auto rounded-2xl flex items-center justify-center text-white text-sm font-bold shadow-sm", tile.iconWrap)}>
                      {id}
                    </div>
                    <Label className={cn("font-semibold text-sm block", tile.title)}>{meta.title}</Label>
                    {needsA ? (
                      <Badge variant="outline" className="text-[10px]">
                        {t("feature_modules.requires_a_badge", { defaultValue: "Requiert A" })}
                      </Badge>
                    ) : null}
                    <p className="text-[11px] text-muted-foreground leading-snug">{meta.desc}</p>
                  </div>
                  <Switch
                    checked={enabled}
                    disabled={readOnly || saving || needsA}
                    onCheckedChange={(checked) => void toggle(key, checked)}
                    aria-label={meta.title}
                  />
                </div>
              </div>
            );
          })}
        </div>

        {modules.moduleD ? (
          <div className="space-y-2 rounded-lg border border-dashed bg-muted/20 p-3">
            <div className="space-y-1 min-w-0">
              <Label className="text-sm font-medium">
                {t("feature_modules.colis_sms_steps", {
                  defaultValue: "SMS colis inclus dans l'offre (module D)",
                })}
              </Label>
              <p className="text-xs text-muted-foreground">
                {t("feature_modules.colis_sms_steps_desc", {
                  defaultValue:
                    "Selon ce que la compagnie paie, choisissez les étapes que l'owner pourra activer. Les étapes non incluses restent verrouillées dans son espace.",
                })}
              </p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2">
              {(
                [
                  ["enregistre", "Enregistrement au guichet", modules.smsEnregistreAllowed],
                  ["charge", "Chargement en soute", modules.smsChargeAllowed],
                  ["arrive", "Arrivée à destination", modules.smsArriveAllowed],
                  ["livre", "Remise au destinataire", modules.smsLivreAllowed],
                ] as const
              ).map(([step, label, allowed]) => (
                <div key={step} className="flex items-center justify-between gap-3">
                  <span className="text-xs">{label}</span>
                  <Switch
                    checked={allowed}
                    disabled={readOnly || saving}
                    onCheckedChange={(checked) => void toggleSmsStep(step, checked)}
                    aria-label={label}
                  />
                </div>
              ))}
            </div>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
