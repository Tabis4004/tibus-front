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
} from "@/lib/supabase/company-feature-modules.ts";

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
    if ((key === "moduleB" || key === "moduleC" || key === "moduleE") && next && !draft.moduleA) {
      toast.error(
        t("feature_modules.requires_a", {
          defaultValue: "Le module A (billetterie) doit être activé en premier.",
        }),
      );
      return;
    }
    setSaving(true);
    try {
      const saved = await setCompanyFeatureModulesSupabase(companyId, {
        moduleA: draft.moduleA,
        moduleB: draft.moduleB,
        moduleC: draft.moduleC,
        moduleD: draft.moduleD,
        moduleE: draft.moduleE,
        moduleF: draft.moduleF,
      });
      setModules(saved);
      toast.success(t("feature_modules.saved", { defaultValue: "Modules mis à jour." }));
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
        <div className="space-y-3">
          {MODULE_ORDER.map((id) => {
            const meta = COMMERCIAL_MODULE_LABELS[id];
            const key = flagKey(id);
            const enabled = Boolean(modules[key]);
            const needsA = (id === "B" || id === "C" || id === "E") && !modules.moduleA;

            return (
              <div
                key={id}
                className="flex items-start justify-between gap-4 rounded-lg border p-3"
              >
                <div className="space-y-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <Label className="font-medium text-sm">{meta.title}</Label>
                    {needsA ? (
                      <Badge variant="outline" className="text-[10px]">
                        {t("feature_modules.requires_a_badge", { defaultValue: "Requiert A" })}
                      </Badge>
                    ) : null}
                  </div>
                  <p className="text-xs text-muted-foreground">{meta.desc}</p>
                </div>
                <Switch
                  checked={enabled}
                  disabled={readOnly || saving || needsA}
                  onCheckedChange={(checked) => void toggle(key, checked)}
                  aria-label={meta.title}
                />
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
