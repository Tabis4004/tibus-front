import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { PackageIcon, PlusIcon, SaveIcon, TrashIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  deleteColisNatureSupabase,
  getCompanyColisSettingsSupabase,
  listColisNaturesSupabase,
  updateCompanyColisSmsSettingsSupabase,
  upsertColisNatureSupabase,
  type ColisNature,
  type CompanyColisSettings,
} from "@/lib/supabase/colis-autonomes.ts";
import { isColisAutonomeModuleActive } from "@/lib/company-feature-modules.ts";
import { useCompanyFeatureModules } from "@/hooks/use-company-feature-modules.ts";

export default function ColisNaturesManager({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const { t: tc } = useTranslation("common");
  const { modules: featureModules, isLoading: modulesLoading } = useCompanyFeatureModules(companyId);
  const [settings, setSettings] = useState<CompanyColisSettings | null>(null);
  const [natures, setNatures] = useState<ColisNature[] | null>(null);
  const [newLibelle, setNewLibelle] = useState("");
  const [savingSms, setSavingSms] = useState(false);
  const [adding, setAdding] = useState(false);

  const load = async () => {
    setNatures(null);
    setSettings(null);
    try {
      const [nextSettings, nextNatures] = await Promise.all([
        getCompanyColisSettingsSupabase(companyId),
        listColisNaturesSupabase(companyId),
      ]);
      setSettings(nextSettings);
      setNatures(nextNatures);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("colis.load_error", { defaultValue: "Chargement impossible" }));
      setSettings(null);
      setNatures([]);
    }
  };

  useEffect(() => {
    void load();
  }, [companyId]);

  const handleAddNature = async () => {
    if (!newLibelle.trim()) return;
    setAdding(true);
    try {
      await upsertColisNatureSupabase(companyId, newLibelle.trim());
      setNewLibelle("");
      toast.success(t("colis.nature_saved", { defaultValue: "Nature enregistrée" }));
      await load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : tc("errors.generic"));
    } finally {
      setAdding(false);
    }
  };

  const handleToggleNature = async (nature: ColisNature) => {
    try {
      await upsertColisNatureSupabase(companyId, nature.libelle, nature.id, !nature.isActive);
      await load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : tc("errors.generic"));
    }
  };

  const handleDeleteNature = async (natureId: string) => {
    try {
      await deleteColisNatureSupabase(natureId);
      toast.success(t("colis.nature_deleted", { defaultValue: "Nature supprimée" }));
      await load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : tc("errors.generic"));
    }
  };

  const handleSaveSms = async () => {
    if (!settings) return;
    setSavingSms(true);
    try {
      const updated = await updateCompanyColisSmsSettingsSupabase(companyId, {
        smsOnEnregistre: settings.smsOnEnregistre,
        smsOnCharge: settings.smsOnCharge,
        smsOnArrive: settings.smsOnArrive,
        smsOnLivre: settings.smsOnLivre,
      });
      setSettings(updated);
      toast.success(t("colis.sms_saved", { defaultValue: "Notifications SMS enregistrées" }));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : tc("errors.generic"));
    } finally {
      setSavingSms(false);
    }
  };

  if (settings === null || natures === null || modulesLoading) {
    return <Skeleton className="h-72 w-full" />;
  }

  const colisModuleActive = isColisAutonomeModuleActive(settings, featureModules);

  if (!colisModuleActive) {
    return (
      <Card>
        <CardContent className="p-6 text-sm text-muted-foreground">
          {t("colis.module_disabled", {
            defaultValue:
              "Le module expédition de colis autonome n'est pas activé pour votre compagnie. Contactez l'administrateur Tibus.",
          })}
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-extrabold">{t("colis.title", { defaultValue: "Colis autonomes" })}</h1>
        <p className="text-sm text-muted-foreground mt-1">
          {t("colis.desc", {
            defaultValue: "Référentiel des natures de colis et notifications SMS par étape.",
          })}
        </p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <PackageIcon className="w-4 h-4" />
            {t("colis.natures_title", { defaultValue: "Natures de colis" })}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <Input
              placeholder={t("colis.nature_placeholder", { defaultValue: "Ex: Carton, Enveloppe…" })}
              value={newLibelle}
              onChange={(e) => setNewLibelle(e.target.value)}
              className="flex-1"
            />
            <Button className="cursor-pointer gap-2 shrink-0" disabled={adding} onClick={() => void handleAddNature()}>
              <PlusIcon className="w-4 h-4" />
              {adding ? "…" : t("colis.add_nature", { defaultValue: "Ajouter" })}
            </Button>
          </div>

          {natures.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("colis.no_natures", { defaultValue: "Aucune nature définie." })}</p>
          ) : (
            <div className="space-y-2">
              {natures.map((nature) => (
                <div key={nature.id} className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2">
                  <div>
                    <p className="font-medium text-sm">{nature.libelle}</p>
                    <p className="text-xs text-muted-foreground">
                      {nature.isActive ? tc("status.active", { defaultValue: "Actif" }) : tc("status.inactive", { defaultValue: "Inactif" })}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <Switch checked={nature.isActive} onCheckedChange={() => void handleToggleNature(nature)} />
                    <Button
                      type="button"
                      size="icon"
                      variant="ghost"
                      className="text-destructive cursor-pointer"
                      onClick={() => void handleDeleteNature(nature.id)}
                    >
                      <TrashIcon className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">{t("colis.sms_title", { defaultValue: "Notifications SMS" })}</CardTitle>
          <p className="text-xs text-muted-foreground">
            {t("colis.sms_desc", {
              defaultValue: "Choisissez les étapes pour lesquelles un SMS est envoyé à l'expéditeur et au destinataire.",
            })}
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          {([
            ["smsOnEnregistre", "colis.sms_enregistre", "Enregistrement au guichet"],
            ["smsOnCharge", "colis.sms_charge", "Chargement en soute"],
            ["smsOnArrive", "colis.sms_arrive", "Arrivée à destination"],
            ["smsOnLivre", "colis.sms_livre", "Remise au destinataire"],
          ] as const).map(([key, labelKey, fallback]) => (
            <div key={key} className="flex items-center justify-between gap-3">
              <Label>{t(labelKey, { defaultValue: fallback })}</Label>
              <Switch
                checked={settings[key]}
                onCheckedChange={(v) => setSettings((prev) => (prev ? { ...prev, [key]: v } : prev))}
              />
            </div>
          ))}
          <Button className="cursor-pointer gap-2" disabled={savingSms} onClick={() => void handleSaveSms()}>
            <SaveIcon className="w-4 h-4" />
            {savingSms ? "…" : tc("buttons.save")}
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
