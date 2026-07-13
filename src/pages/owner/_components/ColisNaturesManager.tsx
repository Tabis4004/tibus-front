import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { CoinsIcon, PackageIcon, PlusIcon, SaveIcon, TrashIcon } from "lucide-react";
import { toast } from "sonner";
import { errorMessage } from "@/lib/utils";
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
  updateCompanyColisPriceSettingsSupabase,
  updateCompanyColisSmsSettingsSupabase,
  upsertColisNatureSupabase,
  type ColisNature,
  type CompanyColisSettings,
} from "@/lib/supabase/colis-autonomes.ts";
import { isColisAutonomeModuleActive } from "@/lib/company-feature-modules.ts";
import { useCompanyFeatureModules } from "@/hooks/use-company-feature-modules.ts";

type NaturePriceDraft = { fixe: string; taux: string };

function naturePriceDraftsFrom(natures: ColisNature[]): Record<string, NaturePriceDraft> {
  return Object.fromEntries(
    natures.map((n) => [
      n.id,
      { fixe: n.prixMinFixe != null ? String(n.prixMinFixe) : "", taux: n.prixMinTaux != null ? String(n.prixMinTaux) : "" },
    ]),
  );
}

export default function ColisNaturesManager({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const { t: tc } = useTranslation("common");
  const { modules: featureModules, isLoading: modulesLoading } = useCompanyFeatureModules(companyId);
  const [settings, setSettings] = useState<CompanyColisSettings | null>(null);
  const [natures, setNatures] = useState<ColisNature[] | null>(null);
  const [newLibelle, setNewLibelle] = useState("");
  const [savingSms, setSavingSms] = useState(false);
  const [adding, setAdding] = useState(false);
  const [naturePriceDrafts, setNaturePriceDrafts] = useState<Record<string, NaturePriceDraft>>({});
  const [savingNaturePriceId, setSavingNaturePriceId] = useState<string | null>(null);
  const [generalPrixMinFixe, setGeneralPrixMinFixe] = useState("");
  const [generalPrixMinTaux, setGeneralPrixMinTaux] = useState("");
  const [generalPourcentagePercu, setGeneralPourcentagePercu] = useState("");
  const [savingGeneralPrice, setSavingGeneralPrice] = useState(false);

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
      setNaturePriceDrafts(naturePriceDraftsFrom(nextNatures));
      setGeneralPrixMinFixe(
        nextSettings.colisPrixMinFixeGeneral != null ? String(nextSettings.colisPrixMinFixeGeneral) : "",
      );
      setGeneralPrixMinTaux(
        nextSettings.colisPrixMinTauxGeneral != null ? String(nextSettings.colisPrixMinTauxGeneral) : "",
      );
      setGeneralPourcentagePercu(
        nextSettings.colisPourcentagePercuGeneral != null
          ? String(nextSettings.colisPourcentagePercuGeneral)
          : "",
      );
    } catch (err) {
      toast.error(errorMessage(err, t("colis.load_error", { defaultValue: "Chargement impossible" })));
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
      toast.error(errorMessage(err, tc("errors.generic")));
    } finally {
      setAdding(false);
    }
  };

  const handleToggleNature = async (nature: ColisNature) => {
    try {
      await upsertColisNatureSupabase(companyId, nature.libelle, nature.id, !nature.isActive);
      await load();
    } catch (err) {
      toast.error(errorMessage(err, tc("errors.generic")));
    }
  };

  const handleDeleteNature = async (natureId: string) => {
    try {
      await deleteColisNatureSupabase(natureId);
      toast.success(t("colis.nature_deleted", { defaultValue: "Nature supprimée" }));
      await load();
    } catch (err) {
      toast.error(errorMessage(err, tc("errors.generic")));
    }
  };

  const handleSaveNaturePrice = async (nature: ColisNature) => {
    const draft = naturePriceDrafts[nature.id] ?? { fixe: "", taux: "" };
    const fixe = draft.fixe.trim() ? Number(draft.fixe) : null;
    const taux = draft.taux.trim() ? Number(draft.taux) : null;
    if ((fixe != null && Number.isNaN(fixe)) || (taux != null && Number.isNaN(taux))) {
      toast.error(t("colis.price_invalid", { defaultValue: "Montant invalide" }));
      return;
    }
    setSavingNaturePriceId(nature.id);
    try {
      await upsertColisNatureSupabase(companyId, nature.libelle, nature.id, nature.isActive, fixe, taux);
      toast.success(t("colis.nature_price_saved", { defaultValue: "Prix minimum enregistré" }));
      await load();
    } catch (err) {
      toast.error(errorMessage(err, tc("errors.generic")));
    } finally {
      setSavingNaturePriceId(null);
    }
  };

  const handleSaveGeneralPrice = async () => {
    const fixe = generalPrixMinFixe.trim() ? Number(generalPrixMinFixe) : null;
    const taux = generalPrixMinTaux.trim() ? Number(generalPrixMinTaux) : null;
    const pourcentage = generalPourcentagePercu.trim() ? Number(generalPourcentagePercu) : null;
    if (
      (fixe != null && Number.isNaN(fixe)) ||
      (taux != null && Number.isNaN(taux)) ||
      (pourcentage != null && (Number.isNaN(pourcentage) || pourcentage < 0 || pourcentage > 100))
    ) {
      toast.error(t("colis.price_invalid", { defaultValue: "Montant invalide" }));
      return;
    }
    setSavingGeneralPrice(true);
    try {
      const updated = await updateCompanyColisPriceSettingsSupabase(companyId, {
        prixMinFixeGeneral: fixe,
        prixMinTauxGeneral: taux,
        pourcentagePercuGeneral: pourcentage,
      });
      setSettings(updated);
      toast.success(t("colis.general_price_saved", { defaultValue: "Prix minimum général enregistré" }));
    } catch (err) {
      toast.error(errorMessage(err, tc("errors.generic")));
    } finally {
      setSavingGeneralPrice(false);
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
      toast.error(errorMessage(err, tc("errors.generic")));
    } finally {
      setSavingSms(false);
    }
  };

  if (settings === null || natures === null || modulesLoading) {
    return <Skeleton className="h-72 w-full" />;
  }

  const colisModuleActive = isColisAutonomeModuleActive(settings, featureModules);
  const smsConfigAllowed = settings.colisSmsConfigEnabled;

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
              {natures.map((nature) => {
                const draft = naturePriceDrafts[nature.id] ?? { fixe: "", taux: "" };
                const priceDirty =
                  draft.fixe !== (nature.prixMinFixe != null ? String(nature.prixMinFixe) : "") ||
                  draft.taux !== (nature.prixMinTaux != null ? String(nature.prixMinTaux) : "");
                return (
                  <div key={nature.id} className="rounded-lg border px-3 py-2 space-y-2">
                    <div className="flex items-center justify-between gap-3">
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
                    <div className="grid grid-cols-2 gap-2 pt-1 border-t">
                      <div className="space-y-1">
                        <Label className="text-[11px] text-muted-foreground font-normal">
                          {t("colis.nature_prix_min_fixe", { defaultValue: "Prix min. fixe (XOF)" })}
                        </Label>
                        <Input
                          type="number"
                          min={0}
                          className="h-8 text-xs"
                          placeholder="—"
                          value={draft.fixe}
                          onChange={(e) =>
                            setNaturePriceDrafts((prev) => ({
                              ...prev,
                              [nature.id]: { ...draft, fixe: e.target.value },
                            }))
                          }
                        />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-[11px] text-muted-foreground font-normal">
                          {t("colis.nature_prix_min_taux", { defaultValue: "Taux min. (XOF/kg)" })}
                        </Label>
                        <Input
                          type="number"
                          min={0}
                          className="h-8 text-xs"
                          placeholder="—"
                          value={draft.taux}
                          onChange={(e) =>
                            setNaturePriceDrafts((prev) => ({
                              ...prev,
                              [nature.id]: { ...draft, taux: e.target.value },
                            }))
                          }
                        />
                      </div>
                    </div>
                    {priceDirty ? (
                      <Button
                        size="sm"
                        variant="secondary"
                        className="h-7 text-xs cursor-pointer gap-1.5"
                        disabled={savingNaturePriceId === nature.id}
                        onClick={() => void handleSaveNaturePrice(nature)}
                      >
                        <SaveIcon className="w-3.5 h-3.5" />
                        {savingNaturePriceId === nature.id
                          ? "…"
                          : t("colis.nature_price_save", { defaultValue: "Enregistrer le prix minimum" })}
                      </Button>
                    ) : null}
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <CoinsIcon className="w-4 h-4" />
            {t("colis.general_price_title", { defaultValue: "Prix minimum général (override)" })}
          </CardTitle>
          <p className="text-xs text-muted-foreground">
            {t("colis.general_price_desc", {
              defaultValue:
                "Si renseigné (fixe ou taux), ce réglage remplace les prix minimums définis par nature pour tous les colis de la compagnie. Laissez vide pour utiliser les règles par nature.",
            })}
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>{t("colis.general_prix_min_fixe", { defaultValue: "Prix minimum fixe (XOF)" })}</Label>
              <Input
                type="number"
                min={0}
                placeholder={t("colis.general_price_placeholder", { defaultValue: "Aucun override" })}
                value={generalPrixMinFixe}
                onChange={(e) => setGeneralPrixMinFixe(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("colis.general_prix_min_taux", { defaultValue: "Taux minimum (XOF/kg)" })}</Label>
              <Input
                type="number"
                min={0}
                placeholder={t("colis.general_price_placeholder", { defaultValue: "Aucun override" })}
                value={generalPrixMinTaux}
                onChange={(e) => setGeneralPrixMinTaux(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>{t("colis.pourcentage_percu_general", { defaultValue: "Pourcentage perçu par défaut (%)" })}</Label>
            <Input
              type="number"
              min={0}
              max={100}
              step="0.1"
              placeholder={t("colis.pourcentage_percu_placeholder", { defaultValue: "Aucun défaut" })}
              value={generalPourcentagePercu}
              onChange={(e) => setGeneralPourcentagePercu(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              {t("colis.pourcentage_percu_desc", {
                defaultValue:
                  "Pré-remplit le pourcentage proposé au guichet quand l'agent choisit de calculer le montant fret automatiquement à partir de la valeur marchandise. Le minimum ci-dessus reste appliqué.",
              })}
            </p>
          </div>
          <Button
            className="cursor-pointer gap-2"
            disabled={savingGeneralPrice}
            onClick={() => void handleSaveGeneralPrice()}
          >
            <SaveIcon className="w-4 h-4" />
            {savingGeneralPrice ? "…" : tc("buttons.save")}
          </Button>
        </CardContent>
      </Card>

      {smsConfigAllowed ? (
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
            ["smsOnEnregistre", "smsAllowedEnregistre", "colis.sms_enregistre", "Enregistrement au guichet"],
            ["smsOnCharge", "smsAllowedCharge", "colis.sms_charge", "Chargement en soute"],
            ["smsOnArrive", "smsAllowedArrive", "colis.sms_arrive", "Arrivée à destination"],
            ["smsOnLivre", "smsAllowedLivre", "colis.sms_livre", "Remise au destinataire"],
          ] as const).map(([key, allowedKey, labelKey, fallback]) => {
            const allowed = settings[allowedKey];
            return (
              <div key={key} className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <Label className={allowed ? undefined : "text-muted-foreground"}>
                    {t(labelKey, { defaultValue: fallback })}
                  </Label>
                  {!allowed ? (
                    <p className="text-[11px] text-muted-foreground">
                      {t("colis.sms_step_locked", {
                        defaultValue: "Non inclus dans votre offre — contactez Tibus.",
                      })}
                    </p>
                  ) : null}
                </div>
                <Switch
                  checked={allowed && settings[key]}
                  disabled={!allowed}
                  onCheckedChange={(v) => setSettings((prev) => (prev ? { ...prev, [key]: v } : prev))}
                />
              </div>
            );
          })}
          <Button className="cursor-pointer gap-2" disabled={savingSms} onClick={() => void handleSaveSms()}>
            <SaveIcon className="w-4 h-4" />
            {savingSms ? "…" : tc("buttons.save")}
          </Button>
        </CardContent>
      </Card>
      ) : (
        <Card>
          <CardContent className="p-4 text-sm text-muted-foreground">
            {t("colis.sms_admin_locked", {
              defaultValue:
                "Les notifications SMS colis ne sont pas activées pour votre offre. Contactez l'administrateur Tibus pour les inclure.",
            })}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
