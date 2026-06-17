import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  ArrowLeftIcon,
  CheckCircleIcon,
  PackageIcon,
  PrinterIcon,
  SearchIcon,
  TruckIcon,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { getSellerProfileSupabase } from "@/lib/supabase/seller-counter";
import { supabaseErrorMessage } from "@/lib/supabase/errors";
import {
  getOpenStationCashSupabase,
  listCompanyStationGaresSupabase,
} from "@/lib/supabase/station-cash.ts";
import { printColisReceipt } from "@/lib/colis-receipt.ts";
import {
  COLIS_NEXT_STATUT,
  COLIS_STATUT_LABELS,
  deliverColisAutonomeSupabase,
  getColisAutonomeDetailSupabase,
  getCompanyColisSettingsSupabase,
  listColisAutonomesSupabase,
  listColisNaturesSupabase,
  registerColisAutonomeSupabase,
  sendColisSmsSupabase,
  updateColisStatutSupabase,
  type ColisAutonomeRow,
  type ColisNature,
  type ColisSmsPayload,
  type ColisStatut,
} from "@/lib/supabase/colis-autonomes.ts";
import { isColisAutonomeModuleActive } from "@/lib/company-feature-modules.ts";
import { getCompanyFeatureModulesSupabase } from "@/lib/supabase/company-feature-modules.ts";
import { cn } from "@/lib/utils.ts";

type GareOption = { id: string; name: string };

function GareNativeSelect({
  value,
  onChange,
  options,
  placeholder,
  disabled,
}: {
  value: string;
  onChange: (value: string) => void;
  options: GareOption[];
  placeholder: string;
  disabled?: boolean;
}) {
  return (
    <select
      className={cn(
        "border-input h-9 w-full min-w-0 rounded-md border bg-transparent px-3 py-1 text-sm shadow-xs transition-[color,box-shadow] outline-none",
        "focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]",
        "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50",
        !value && "text-muted-foreground",
      )}
      value={value}
      onChange={(event) => onChange(event.target.value)}
      disabled={disabled}
    >
      <option value="" disabled>
        {placeholder}
      </option>
      {options.map((gare) => (
        <option key={gare.id} value={gare.id}>
          {gare.name}
        </option>
      ))}
    </select>
  );
}

async function maybeSendColisSms(
  colisId: string,
  statut: ColisStatut,
  sms: ColisSmsPayload,
) {
  if (!sms.send || !sms.message) {
    toast.message("SMS non envoyé — activez « Enregistrement au guichet » dans Paramètres colis (owner).");
    return;
  }
  const phones = [sms.expediteurPhone, sms.destinatairePhone].filter(Boolean) as string[];
  if (!phones.length) {
    toast.error("Numéros expéditeur / destinataire manquants pour le SMS");
    return;
  }
  try {
    const result = await sendColisSmsSupabase({ colisId, statut, message: sms.message, phones });
    if (result.failed > 0) {
      toast.warning(`SMS : ${result.sent} envoyé(s), ${result.failed} échec(s)`);
    } else {
      toast.success(`SMS envoyé à ${result.sent} numéro(s)`);
    }
  } catch (err) {
    toast.error(err instanceof Error ? err.message : "Échec envoi SMS colis");
  }
}

export default function ColisAutonomesPage({
  onBack,
  companyId: companyIdProp,
  companyName: companyNameProp,
}: {
  onBack?: () => void;
  companyId?: string;
  companyName?: string;
}) {
  const { t } = useTranslation("seller");
  const { appUserId } = useSupabaseAuth();
  const [loading, setLoading] = useState(true);
  const [moduleEnabled, setModuleEnabled] = useState(false);
  const [companyId, setCompanyId] = useState<string | null>(null);
  const [companyName, setCompanyName] = useState("");
  const [gares, setGares] = useState<GareOption[]>([]);
  const [natures, setNatures] = useState<ColisNature[]>([]);
  const [rows, setRows] = useState<ColisAutonomeRow[]>([]);
  const [filterStatut, setFilterStatut] = useState<ColisStatut | "all">("all");

  const [gareDepartId, setGareDepartId] = useState("");
  const [gareDestinationId, setGareDestinationId] = useState("");
  const [cashGareId, setCashGareId] = useState<string | null>(null);
  const [nomExpediteur, setNomExpediteur] = useState("");
  const [telephoneExpediteur, setTelephoneExpediteur] = useState("");
  const [nomDestinataire, setNomDestinataire] = useState("");
  const [telephoneDestinataire, setTelephoneDestinataire] = useState("");
  const [descriptionContenu, setDescriptionContenu] = useState("");
  const [poidsKg, setPoidsKg] = useState("");
  const [nombrePieces, setNombrePieces] = useState("1");
  const [montantFret, setMontantFret] = useState("");
  const [selectedNatureId, setSelectedNatureId] = useState("");
  const [saving, setSaving] = useState(false);
  const [lastRegisteredId, setLastRegisteredId] = useState<string | null>(null);

  const [retraitCode, setRetraitCode] = useState("");
  const [delivering, setDelivering] = useState(false);

  const activeNatures = useMemo(
    () => natures.filter((n) => n.isActive),
    [natures],
  );

  const destinationGares = useMemo(
    () => gares.filter((g) => g.id !== gareDepartId),
    [gares, gareDepartId],
  );
  const departureGares = useMemo(
    () => (gareDepartId ? gares.filter((g) => g.id === gareDepartId) : gares),
    [gares, gareDepartId],
  );
  const departureLocked = Boolean(gareDepartId);
  const departureLockedByCash = Boolean(cashGareId && gareDepartId === cashGareId);

  useEffect(() => {
    if (gareDestinationId && gareDestinationId === gareDepartId) {
      setGareDestinationId("");
    }
  }, [gareDepartId, gareDestinationId]);

  const filteredRows = useMemo(() => {
    if (filterStatut === "all") return rows;
    return rows.filter((r) => r.statutColis === filterStatut);
  }, [rows, filterStatut]);

  const load = async () => {
    if (!appUserId && !companyIdProp) return;
    setLoading(true);
    try {
      let cid = companyIdProp ?? null;
      if (!cid && appUserId) {
        const profile = await getSellerProfileSupabase(appUserId);
        if (!profile?.company?.id) {
          setModuleEnabled(false);
          setCompanyId(null);
          return;
        }
        cid = profile.company.id;
        setCompanyName(profile.company.name);
      } else if (companyNameProp) {
        setCompanyName(companyNameProp);
      }
      if (!cid) {
        setModuleEnabled(false);
        setCompanyId(null);
        return;
      }
      setCompanyId(cid);

      const [settings, featureModules] = await Promise.all([
        getCompanyColisSettingsSupabase(cid),
        getCompanyFeatureModulesSupabase(cid).catch(() => null),
      ]);
      const moduleActive = isColisAutonomeModuleActive(settings, featureModules);
      setModuleEnabled(moduleActive);
      if (!moduleActive) return;

      const [garesResult, naturesResult, listResult, openCashResult] = await Promise.allSettled([
        listCompanyStationGaresSupabase(cid),
        listColisNaturesSupabase(cid),
        listColisAutonomesSupabase(cid),
        getOpenStationCashSupabase(),
      ]);

      const nextGares = garesResult.status === "fulfilled" ? garesResult.value : [];
      const nextNatures = naturesResult.status === "fulfilled" ? naturesResult.value : [];
      const nextRows = listResult.status === "fulfilled" ? listResult.value : [];

      const loadErrors: string[] = [];
      if (garesResult.status === "rejected") {
        loadErrors.push(`Gares : ${supabaseErrorMessage(garesResult.reason)}`);
      }
      if (naturesResult.status === "rejected") {
        loadErrors.push(`Natures : ${supabaseErrorMessage(naturesResult.reason)}`);
      }
      if (listResult.status === "rejected") {
        loadErrors.push(`Liste colis : ${supabaseErrorMessage(listResult.reason)}`);
      }

      setGares(nextGares);
      setNatures(nextNatures.filter((n) => n.isActive));
      setRows(nextRows);

      const openCash =
        openCashResult.status === "fulfilled" ? openCashResult.value : null;
      if (openCash?.open && openCash.gareId) {
        setCashGareId(openCash.gareId);
        setGareDepartId(openCash.gareId);
      } else {
        setCashGareId(null);
      }

      if (loadErrors.length) {
        toast.error(loadErrors.join(" · "));
      } else if (!nextGares.length) {
        toast.message(
          t("colis.no_gares", {
            defaultValue: "Aucune gare configurée. Ajoutez des gares dans la console owner.",
          }),
        );
      }
    } catch (err) {
      toast.error(
        supabaseErrorMessage(
          err,
          t("colis.load_error", { defaultValue: "Chargement impossible" }),
        ),
      );
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, [appUserId, companyIdProp, companyNameProp]);

  const handleRegister = async () => {
    if (!companyId) return;
    if (!gareDepartId || !gareDestinationId) {
      toast.error(t("colis.gares_required", { defaultValue: "Sélectionnez les gares" }));
      return;
    }
    if (cashGareId && gareDepartId !== cashGareId) {
      toast.error(
        t("colis.cash_gare_only", {
          defaultValue: "L'expédition cash doit partir de votre gare de caisse ouverte.",
        }),
      );
      return;
    }
    if (gareDepartId === gareDestinationId) {
      toast.error(
        t("colis.same_gare", {
          defaultValue: "La gare de destination doit être différente de la gare de départ.",
        }),
      );
      return;
    }
    if (!nomExpediteur.trim() || !nomDestinataire.trim()) {
      toast.error(t("colis.names_required", { defaultValue: "Nom expéditeur et destinataire requis" }));
      return;
    }
    if (!telephoneExpediteur.trim() || !telephoneDestinataire.trim()) {
      toast.error(t("colis.phones_required", { defaultValue: "Téléphones expéditeur et destinataire requis" }));
      return;
    }
    if (!selectedNatureId) {
      toast.error(t("colis.nature_required", { defaultValue: "Sélectionnez une nature de colis" }));
      return;
    }
    setSaving(true);
    try {
      const result = await registerColisAutonomeSupabase({
        companyId,
        gareDepartId,
        gareDestinationId,
        nomExpediteur,
        telephoneExpediteur,
        nomDestinataire,
        telephoneDestinataire,
        descriptionContenu,
        poidsKg: poidsKg ? Number(poidsKg) : undefined,
        nombrePieces: Number(nombrePieces) || 1,
        montantFret: Number(montantFret) || 0,
        natureIds: [selectedNatureId],
      });
      await maybeSendColisSms(result.id, result.statutColis, result.sms);
      setLastRegisteredId(result.id);
      toast.success(t("colis.registered", { defaultValue: "Colis enregistré — encaissement guichet" }));
      window.dispatchEvent(new CustomEvent("tibus:station-cash-refresh"));
      try {
        const detail = await getColisAutonomeDetailSupabase(result.id);
        if (detail) await printColisReceipt(detail);
      } catch {
        toast.message("Colis enregistré — impression manuelle via le bouton Imprimer");
      }
      await load();
    } catch (err) {
      toast.error(
        supabaseErrorMessage(err, t("errors.generic", { ns: "common" })),
      );
    } finally {
      setSaving(false);
    }
  };

  const handlePrint = async (colisId: string) => {
    try {
      const detail = await getColisAutonomeDetailSupabase(colisId);
      if (!detail) throw new Error("Colis introuvable");
      await printColisReceipt(detail);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Impression impossible");
    }
  };

  const handleAdvanceStatus = async (row: ColisAutonomeRow) => {
    const next = COLIS_NEXT_STATUT[row.statutColis];
    if (!next || next === "livre") return;
    try {
      const result = await updateColisStatutSupabase(row.id, next);
      await maybeSendColisSms(result.id, result.statutColis, result.sms);
      toast.success(`${COLIS_STATUT_LABELS[result.statutColis]}`);
      await load();
    } catch (err) {
      toast.error(supabaseErrorMessage(err, t("errors.generic", { ns: "common" })));
    }
  };

  const handleDeliver = async () => {
    if (!retraitCode.trim()) return;
    setDelivering(true);
    try {
      const result = await deliverColisAutonomeSupabase(retraitCode.trim());
      await maybeSendColisSms(result.id, result.statutColis, result.sms);
      toast.success(
        t("colis.delivered", {
          defaultValue: "Colis remis à {{name}}",
          name: result.nomDestinataire,
        }),
      );
      setRetraitCode("");
      await load();
    } catch (err) {
      toast.error(supabaseErrorMessage(err, t("colis.invalid_code", { defaultValue: "Code invalide" })));
    } finally {
      setDelivering(false);
    }
  };

  if (loading) {
    return (
      <div className="space-y-3">
        <Skeleton className="h-10 w-48" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  if (!companyId || !moduleEnabled) {
    return (
      <Card>
        <CardContent className="p-8 text-center text-muted-foreground space-y-2">
          <PackageIcon className="w-10 h-10 mx-auto opacity-30" />
          <p className="font-medium">{t("colis.unavailable", { defaultValue: "Module colis non disponible" })}</p>
          {onBack ? (
            <Button variant="ghost" className="cursor-pointer" onClick={onBack}>
              <ArrowLeftIcon className="w-4 h-4 mr-1" /> Retour
            </Button>
          ) : null}
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-2">
        <div>
          <h2 className="text-lg font-extrabold">{t("colis.title", { defaultValue: "Expédition de colis" })}</h2>
          <p className="text-xs text-muted-foreground">{companyName}</p>
        </div>
        {onBack ? (
          <Button variant="ghost" size="sm" className="cursor-pointer" onClick={onBack}>
            <ArrowLeftIcon className="w-4 h-4" />
          </Button>
        ) : null}
      </div>

      <Tabs defaultValue="expedition">
        <TabsList className="w-full">
          <TabsTrigger value="expedition" className="flex-1 cursor-pointer">
            {t("colis.tab_register", { defaultValue: "Enregistrer" })}
          </TabsTrigger>
          <TabsTrigger value="suivi" className="flex-1 cursor-pointer">
            {t("colis.tab_track", { defaultValue: "Suivi" })}
          </TabsTrigger>
          <TabsTrigger value="retrait" className="flex-1 cursor-pointer">
            {t("colis.tab_pickup", { defaultValue: "Retrait" })}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="expedition" className="space-y-4 mt-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">{t("colis.form_title", { defaultValue: "Nouvel envoi gare à gare" })}</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid sm:grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <div className="flex items-center justify-between gap-2">
                    <Label>{t("colis.gare_depart", { defaultValue: "Gare de départ" })}</Label>
                    {departureLocked && !departureLockedByCash ? (
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="h-7 px-2 text-xs cursor-pointer"
                        onClick={() => {
                          setGareDepartId("");
                          setGareDestinationId("");
                        }}
                      >
                        Changer
                      </Button>
                    ) : null}
                  </div>
                  <GareNativeSelect
                    value={gareDepartId}
                    onChange={setGareDepartId}
                    options={departureGares}
                    placeholder={t("colis.gare_placeholder", { defaultValue: "Choisir une gare" })}
                    disabled={!gares.length}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>{t("colis.gare_destination", { defaultValue: "Gare de destination" })}</Label>
                  <GareNativeSelect
                    value={gareDestinationId}
                    onChange={setGareDestinationId}
                    options={destinationGares}
                    placeholder={
                      gareDepartId
                        ? t("colis.gare_placeholder", { defaultValue: "Choisir une gare" })
                        : t("colis.gare_depart_first", { defaultValue: "Choisissez d'abord le départ" })
                    }
                    disabled={!gareDepartId || destinationGares.length === 0}
                  />
                </div>
                {!gares.length ? (
                  <p className="sm:col-span-2 text-xs text-amber-700 dark:text-amber-400">
                    {t("colis.no_gares_hint", {
                      defaultValue:
                        "Aucune gare chargée. Vérifiez la connexion ou ajoutez des gares dans la console owner.",
                    })}
                  </p>
                ) : null}
              </div>

              <div className="grid sm:grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label>{t("colis.expediteur", { defaultValue: "Expéditeur" })}</Label>
                  <Input value={nomExpediteur} onChange={(e) => setNomExpediteur(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label>{t("colis.tel_expediteur", { defaultValue: "Tél. expéditeur" })}</Label>
                  <Input value={telephoneExpediteur} onChange={(e) => setTelephoneExpediteur(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label>{t("colis.destinataire", { defaultValue: "Destinataire" })}</Label>
                  <Input value={nomDestinataire} onChange={(e) => setNomDestinataire(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label>{t("colis.tel_destinataire", { defaultValue: "Tél. destinataire" })}</Label>
                  <Input value={telephoneDestinataire} onChange={(e) => setTelephoneDestinataire(e.target.value)} />
                </div>
              </div>

              <div className="space-y-1.5">
                <Label>{t("colis.nature", { defaultValue: "Nature de colis" })}</Label>
                <Select value={selectedNatureId || undefined} onValueChange={setSelectedNatureId}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder={t("colis.nature_placeholder", { defaultValue: "Choisir une nature" })} />
                  </SelectTrigger>
                  <SelectContent className="z-[200] max-h-72">
                    {activeNatures.map((nature) => (
                      <SelectItem key={nature.id} value={nature.id}>
                        {nature.libelle}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-1.5">
                <Label>{t("colis.description", { defaultValue: "Description du contenu" })}</Label>
                <Input value={descriptionContenu} onChange={(e) => setDescriptionContenu(e.target.value)} />
              </div>

              <div className="grid grid-cols-3 gap-3">
                <div className="space-y-1.5">
                  <Label>{t("colis.poids", { defaultValue: "Poids (kg)" })}</Label>
                  <Input type="number" min={0} step="0.1" value={poidsKg} onChange={(e) => setPoidsKg(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label>{t("colis.pieces", { defaultValue: "Pièces" })}</Label>
                  <Input type="number" min={1} value={nombrePieces} onChange={(e) => setNombrePieces(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label>{t("colis.montant", { defaultValue: "Montant fret (XOF)" })}</Label>
                  <Input type="number" min={0} value={montantFret} onChange={(e) => setMontantFret(e.target.value)} />
                </div>
              </div>

              <Button className="w-full cursor-pointer" disabled={saving} onClick={() => void handleRegister()}>
                {saving ? "…" : t("colis.register_btn", { defaultValue: "Enregistrer & encaisser" })}
              </Button>

              {lastRegisteredId ? (
                <div className="rounded-lg border border-green-500/30 bg-green-500/5 p-3 space-y-2">
                  <p className="text-sm font-medium flex items-center gap-2">
                    <CheckCircleIcon className="w-4 h-4 text-green-600" />
                    {t("colis.code_retrait", { defaultValue: "Code de retrait" })}
                  </p>
                  <p className="font-mono text-xs break-all">{lastRegisteredId}</p>
                  <Button variant="outline" size="sm" className="cursor-pointer gap-2" onClick={() => void handlePrint(lastRegisteredId)}>
                    <PrinterIcon className="w-4 h-4" />
                    {t("colis.print_receipt", { defaultValue: "Imprimer le reçu" })}
                  </Button>
                </div>
              ) : null}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="suivi" className="space-y-3 mt-4">
          <Select value={filterStatut} onValueChange={(v) => setFilterStatut(v as ColisStatut | "all")}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tous</SelectItem>
              {(Object.keys(COLIS_STATUT_LABELS) as ColisStatut[]).map((s) => (
                <SelectItem key={s} value={s}>{COLIS_STATUT_LABELS[s]}</SelectItem>
              ))}
            </SelectContent>
          </Select>

          {filteredRows.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-8">Aucun colis</p>
          ) : (
            filteredRows.map((row) => {
              const next = COLIS_NEXT_STATUT[row.statutColis];
              return (
                <Card key={row.id}>
                  <CardContent className="p-4 space-y-2">
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <p className="font-semibold text-sm">{row.gareDepart} → {row.gareDestination}</p>
                        <p className="text-xs text-muted-foreground">{row.nomExpediteur} → {row.nomDestinataire}</p>
                        <p className="font-mono text-[10px] text-muted-foreground mt-1 break-all">{row.id}</p>
                      </div>
                      <Badge variant="secondary">{COLIS_STATUT_LABELS[row.statutColis]}</Badge>
                    </div>
                    <p className="text-xs">{row.natures.join(", ")} · {row.montantFret.toLocaleString()} XOF</p>
                    <div className="flex gap-2 flex-wrap">
                      {next && next !== "livre" ? (
                        <Button size="sm" variant="secondary" className="cursor-pointer gap-1" onClick={() => void handleAdvanceStatus(row)}>
                          <TruckIcon className="w-3.5 h-3.5" />
                          → {COLIS_STATUT_LABELS[next]}
                        </Button>
                      ) : null}
                      <Button size="sm" variant="outline" className="cursor-pointer gap-1" onClick={() => void handlePrint(row.id)}>
                        <PrinterIcon className="w-3.5 h-3.5" /> Reçu
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              );
            })
          )}
        </TabsContent>

        <TabsContent value="retrait" className="space-y-4 mt-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">{t("colis.pickup_title", { defaultValue: "Remise au destinataire" })}</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <p className="text-xs text-muted-foreground">
                {t("colis.pickup_hint", {
                  defaultValue: "Saisissez le code de retrait (UUID du colis). Le colis doit être au statut « Arrivé ».",
                })}
              </p>
              <div className="flex gap-2">
                <Input
                  className="font-mono text-xs"
                  placeholder="Code de retrait (UUID)"
                  value={retraitCode}
                  onChange={(e) => setRetraitCode(e.target.value)}
                />
                <Button className="cursor-pointer shrink-0 gap-2" disabled={delivering} onClick={() => void handleDeliver()}>
                  <SearchIcon className="w-4 h-4" />
                  {delivering ? "…" : t("colis.deliver_btn", { defaultValue: "Remettre" })}
                </Button>
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
