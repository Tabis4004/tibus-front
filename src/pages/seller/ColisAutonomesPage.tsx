import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  ArrowLeftIcon,
  MessageCircleIcon,
  PackageIcon,
  PrinterIcon,
  TruckIcon,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
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
import ColisReceiptPanel from "@/components/seller/ColisReceiptPanel.tsx";
import ColisScanWorkflow from "@/pages/verify/_components/ColisScanWorkflow.tsx";
import BordereauPanel from "@/pages/seller/_components/BordereauPanel.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { getSellerProfileSupabase, getSellerCompanyReceiptInfoSupabase, type SellerCompanyReceiptInfo } from "@/lib/supabase/seller-counter";
import { supabaseErrorMessage } from "@/lib/supabase/errors";
import {
  getOpenStationCashSupabase,
  listCompanyStationGaresSupabase,
} from "@/lib/supabase/station-cash.ts";
import {
  COLIS_NEXT_STATUT,
  COLIS_STATUT_LABELS,
  getColisAutonomeDetailSupabase,
  getColisPrixMinSupabase,
  getCompanyColisSettingsSupabase,
  listColisAutonomesSupabase,
  listColisNaturesSupabase,
  listCompanyBusesSupabase,
  registerColisAutonomeSupabase,
  sendColisSmsSupabase,
  updateColisStatutSupabase,
  type ColisAutonomeDetail,
  type ColisAutonomeRow,
  type ColisBusOption,
  type ColisNature,
  type ColisSmsPayload,
  type ColisStatut,
  type CompanyColisSettings,
} from "@/lib/supabase/colis-autonomes.ts";
import { buildColisTrackingWhatsAppMessage, openColisWhatsApp } from "@/lib/colis-receipt.ts";
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
    console.info("[colis-sms-skipped]", { statut, skipReason: sms.skipReason, send: sms.send });
    if (sms.skipReason === "admin_gate") {
      toast.message(
        "SMS non envoyé — l'administrateur Tibus doit activer « Configuration SMS colis » pour votre compagnie.",
      );
      return;
    }
    toast.message(
      "SMS non envoyé — activez l'étape correspondante dans Paramètres colis (owner).",
    );
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
    const message = err instanceof Error ? err.message : "Échec envoi SMS colis";
    console.error("[colis-sms-client]", message, err);
    toast.error(message, { duration: 12000 });
  }
}

export default function ColisAutonomesPage({
  onBack,
  companyId: companyIdProp,
  companyName: companyNameProp,
  companyReceiptInfo: companyReceiptInfoProp,
}: {
  onBack?: () => void;
  companyId?: string;
  companyName?: string;
  companyReceiptInfo?: SellerCompanyReceiptInfo | null;
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
  const [filterGareDepart, setFilterGareDepart] = useState<string>("all");
  const [filterGareDest, setFilterGareDest] = useState<string>("all");
  const [filterExpediteur, setFilterExpediteur] = useState("");
  const [filterDestinataire, setFilterDestinataire] = useState("");
  const [filterReference, setFilterReference] = useState("");
  const [filterBus, setFilterBus] = useState<string>("all");
  const [buses, setBuses] = useState<ColisBusOption[]>([]);
  // Bus sélectionné (par colis) juste avant de confirmer "Charger en soute".
  const [busSelections, setBusSelections] = useState<Record<string, string>>({});

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
  const [valeurMarchandise, setValeurMarchandise] = useState("");
  const [montantMode, setMontantMode] = useState<"manuel" | "auto">("manuel");
  const [pourcentagePercu, setPourcentagePercu] = useState("");
  const [selectedNatureId, setSelectedNatureId] = useState("");
  const [saving, setSaving] = useState(false);
  const [prixMinSuggere, setPrixMinSuggere] = useState<number | null>(null);
  const [receiptDetail, setReceiptDetail] = useState<ColisAutonomeDetail | null>(null);
  const [companyReceiptInfo, setCompanyReceiptInfo] = useState<SellerCompanyReceiptInfo | null>(
    companyReceiptInfoProp ?? null,
  );
  const [companySettings, setCompanySettings] = useState<CompanyColisSettings | null>(null);

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

  // Listes de gares présentes dans les envois (pour les filtres de suivi).
  const suiviGaresDepart = useMemo(
    () => [...new Set(rows.map((r) => r.gareDepart).filter(Boolean))].sort((a, b) => a.localeCompare(b, "fr")),
    [rows],
  );
  const suiviGaresDest = useMemo(
    () => [...new Set(rows.map((r) => r.gareDestination).filter(Boolean))].sort((a, b) => a.localeCompare(b, "fr")),
    [rows],
  );
  const suiviBuses = useMemo(
    () => [...new Set(rows.map((r) => r.busPlateNumber).filter((v): v is string => Boolean(v)))].sort((a, b) => a.localeCompare(b, "fr")),
    [rows],
  );

  const filteredRows = useMemo(() => {
    const norm = (v: string) => v.trim().toLowerCase();
    const expQ = norm(filterExpediteur);
    const destQ = norm(filterDestinataire);
    // Référence : accepte CL-XXXX, l'id complet ou un fragment.
    const refQ = norm(filterReference).replace(/^cl-?/, "");
    return rows.filter((r) => {
      if (filterStatut !== "all" && r.statutColis !== filterStatut) return false;
      if (filterGareDepart !== "all" && r.gareDepart !== filterGareDepart) return false;
      if (filterGareDest !== "all" && r.gareDestination !== filterGareDest) return false;
      if (filterBus !== "all" && r.busPlateNumber !== filterBus) return false;
      if (
        expQ &&
        !norm(r.nomExpediteur).includes(expQ) &&
        !norm(r.telephoneExpediteur).replace(/\s/g, "").includes(expQ.replace(/\s/g, ""))
      ) {
        return false;
      }
      if (
        destQ &&
        !norm(r.nomDestinataire).includes(destQ) &&
        !norm(r.telephoneDestinataire).replace(/\s/g, "").includes(destQ.replace(/\s/g, ""))
      ) {
        return false;
      }
      if (refQ && !norm(r.id).includes(refQ)) return false;
      return true;
    });
  }, [rows, filterStatut, filterGareDepart, filterGareDest, filterBus, filterExpediteur, filterDestinataire, filterReference]);

  const resetExpeditionForm = () => {
    setNomExpediteur("");
    setTelephoneExpediteur("");
    setNomDestinataire("");
    setTelephoneDestinataire("");
    setDescriptionContenu("");
    setPoidsKg("");
    setNombrePieces("1");
    setMontantFret("");
    setValeurMarchandise("");
    setSelectedNatureId("");
    setPrixMinSuggere(null);
    if (cashGareId) setGareDepartId(cashGareId);
    else setGareDepartId("");
    setGareDestinationId("");
  };

  const refreshListSilently = async (cid = companyId) => {
    if (!cid) return;
    try {
      const nextRows = await listColisAutonomesSupabase(cid);
      setRows(nextRows);
    } catch {
      // liste rafraîchie au prochain chargement complet
    }
  };

  const notifyCashRefresh = () => {
    window.dispatchEvent(new CustomEvent("tibus:station-cash-refresh"));
  };

  const closeReceipt = (options?: { newShipment?: boolean }) => {
    setReceiptDetail(null);
    void refreshListSilently();
    notifyCashRefresh();
    if (options?.newShipment) {
      resetExpeditionForm();
    }
  };

  const load = async () => {
    if (!appUserId && !companyIdProp) return;
    setLoading(true);
    try {
      // Caisse éventuellement ouverte par l'agent : sa compagnie (companyId,
      // exposé par la RPC depuis la migration 170) est la seule source de
      // vérité fiable pour la "compagnie active" d'un vendeur multi-
      // compagnies. On la récupère avant de résoudre `cid` pour la préférer
      // à l'heuristique "première compagnie où l'utilisateur a un rôle"
      // ci-dessous — sinon la liste des gares peut être chargée pour une
      // compagnie différente de celle de la caisse ouverte, et gareDepartId
      // (calé sur la caisse) ne correspond à aucune gare de la liste : le
      // <select> "Gare de départ" reste alors vide (aucune <option> ne
      // matche sa valeur). Même classe de bug déjà corrigée côté
      // courrier_mobile (providers.dart / activeCompanyIdProvider).
      const earlyOpenCash = await getOpenStationCashSupabase().catch(() => null);

      let cid = companyIdProp ?? null;
      if (!cid && appUserId) {
        const profile = await getSellerProfileSupabase(
          appUserId,
          earlyOpenCash?.companyId ?? null,
        );
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

      const receiptInfoPromise = companyReceiptInfoProp
        ? Promise.resolve(companyReceiptInfoProp)
        : getSellerCompanyReceiptInfoSupabase(cid).catch(() => null);

      const [settings, featureModules, receiptInfo] = await Promise.all([
        getCompanyColisSettingsSupabase(cid),
        getCompanyFeatureModulesSupabase(cid).catch(() => null),
        receiptInfoPromise,
      ]);
      setCompanyReceiptInfo(receiptInfo);
      setCompanySettings(settings);
      setPourcentagePercu((prev) =>
        prev
          ? prev
          : settings.colisPourcentagePercuGeneral != null
            ? String(settings.colisPourcentagePercuGeneral)
            : prev,
      );
      const moduleActive = isColisAutonomeModuleActive(settings, featureModules);
      setModuleEnabled(moduleActive);
      if (!moduleActive) return;

      const [garesResult, naturesResult, listResult, busesResult] = await Promise.allSettled([
        listCompanyStationGaresSupabase(cid),
        listColisNaturesSupabase(cid),
        listColisAutonomesSupabase(cid),
        listCompanyBusesSupabase(cid),
      ]);

      const nextGares = garesResult.status === "fulfilled" ? garesResult.value : [];
      const nextNatures = naturesResult.status === "fulfilled" ? naturesResult.value : [];
      const nextRows = listResult.status === "fulfilled" ? listResult.value : [];
      const nextBuses = busesResult.status === "fulfilled" ? busesResult.value : [];

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
      setBuses(nextBuses);

      const openCash = earlyOpenCash;
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

  // Prix minimum indicatif (règles owner : par nature ou override général) —
  // purement informatif côté client, la validation finale est faite en base.
  useEffect(() => {
    if (!companyId || !selectedNatureId) {
      setPrixMinSuggere(null);
      return;
    }
    let cancelled = false;
    const poids = poidsKg ? Number(poidsKg) : null;
    getColisPrixMinSupabase(companyId, [selectedNatureId], poids)
      .then((min) => {
        if (!cancelled) setPrixMinSuggere(min > 0 ? min : null);
      })
      .catch(() => {
        if (!cancelled) setPrixMinSuggere(null);
      });
    return () => {
      cancelled = true;
    };
  }, [companyId, selectedNatureId, poidsKg]);

  // Calcul automatique du montant fret = pourcentage perçu × valeur marchandise,
  // remonté au minimum requis (prixMinSuggere) le cas échéant. Le mode "manuel"
  // laisse l'agent saisir librement le montant fret.
  useEffect(() => {
    if (montantMode !== "auto") return;
    const valeur = Number(valeurMarchandise) || 0;
    const pct = Number(pourcentagePercu) || 0;
    if (valeur <= 0 || pct <= 0) {
      setMontantFret("");
      return;
    }
    const calcule = Math.round((valeur * pct) / 100);
    const applique = prixMinSuggere != null ? Math.max(calcule, Math.round(prixMinSuggere)) : calcule;
    setMontantFret(String(applique));
  }, [montantMode, valeurMarchandise, pourcentagePercu, prixMinSuggere]);

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
    if (!valeurMarchandise.trim() || (Number(valeurMarchandise) || 0) <= 0) {
      toast.error(
        t("colis.valeur_marchandise_required", {
          defaultValue:
            "Valeur marchandise obligatoire — elle sert de base au remboursement en cas de perte.",
        }),
      );
      return;
    }
    if (montantMode === "auto" && (!pourcentagePercu.trim() || (Number(pourcentagePercu) || 0) <= 0)) {
      toast.error(
        t("colis.pourcentage_percu_required", {
          defaultValue: "Renseignez le pourcentage perçu pour le calcul automatique",
        }),
      );
      return;
    }
    if (prixMinSuggere != null && (Number(montantFret) || 0) < prixMinSuggere) {
      toast.error(
        t("colis.montant_below_min", {
          defaultValue: `Montant fret insuffisant — minimum requis ${prixMinSuggere.toLocaleString()} XOF`,
          amount: prixMinSuggere.toLocaleString(),
        }),
      );
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
        valeurMarchandise: Number(valeurMarchandise),
        pourcentagePercu: montantMode === "auto" ? Number(pourcentagePercu) || undefined : undefined,
        natureIds: [selectedNatureId],
      });
      const detail = await getColisAutonomeDetailSupabase(result.id);
      if (!detail) {
        throw new Error("Colis enregistré mais reçu indisponible — consultez l'onglet Suivi.");
      }
      resetExpeditionForm();
      setReceiptDetail(detail);
      void maybeSendColisSms(result.id, result.statutColis, result.sms);
      toast.success(t("colis.registered", { defaultValue: "Colis enregistré — encaissement guichet" }));
    } catch (err) {
      toast.error(
        supabaseErrorMessage(err, t("errors.generic", { ns: "common" })),
      );
    } finally {
      setSaving(false);
    }
  };

  const handleShowReceipt = async (colisId: string) => {
    try {
      const detail = await getColisAutonomeDetailSupabase(colisId);
      if (!detail) throw new Error("Colis introuvable");
      setReceiptDetail(detail);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Reçu indisponible");
    }
  };

  const handleColisWhatsApp = (row: ColisAutonomeRow, recipient: "expediteur" | "destinataire") => {
    const phone = recipient === "expediteur" ? row.telephoneExpediteur : row.telephoneDestinataire;
    const message = buildColisTrackingWhatsAppMessage({
      colisId: row.id,
      statut: row.statutColis,
      companyName,
      gareDepart: row.gareDepart,
      gareDestination: row.gareDestination,
      recipientLabel: recipient === "expediteur" ? "Expéditeur" : "Destinataire",
    });
    openColisWhatsApp(phone, message);
  };

  const handleAdvanceStatus = async (row: ColisAutonomeRow) => {
    const next = COLIS_NEXT_STATUT[row.statutColis];
    if (!next || next === "livre") return;
    try {
      const busId = next === "charge" ? busSelections[row.id] || null : null;
      const result = await updateColisStatutSupabase(row.id, next, busId);
      await maybeSendColisSms(result.id, result.statutColis, result.sms);
      toast.success(`${COLIS_STATUT_LABELS[result.statutColis]}`);
      setBusSelections((prev) => {
        const updated = { ...prev };
        delete updated[row.id];
        return updated;
      });
      await load();
    } catch (err) {
      toast.error(supabaseErrorMessage(err, t("errors.generic", { ns: "common" })));
    }
  };

  if (receiptDetail) {
    return (
      <ColisReceiptPanel
        detail={receiptDetail}
        companyInfo={companyReceiptInfo ?? undefined}
        autoPrint
        onBack={() => {
          closeReceipt();
          onBack?.();
        }}
        onNewShipment={() => closeReceipt({ newShipment: true })}
        onDone={() => closeReceipt()}
      />
    );
  }

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
          <TabsTrigger value="bordereau" className="flex-1 cursor-pointer">
            {t("colis.tab_bordereau", { defaultValue: "Bordereaux" })}
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
                  <Label>
                    {t("colis.valeur_marchandise", { defaultValue: "Valeur marchandise (XOF)" })}
                    <span className="text-destructive"> *</span>
                  </Label>
                  <Input
                    type="number"
                    min={0}
                    value={valeurMarchandise}
                    onChange={(e) => setValeurMarchandise(e.target.value)}
                    placeholder={t("colis.valeur_marchandise_placeholder", { defaultValue: "Obligatoire" })}
                  />
                </div>
              </div>

              <div className="rounded-lg border p-3 space-y-3">
                <div className="flex items-center justify-between gap-2">
                  <div>
                    <Label className="mb-0.5 block">
                      {t("colis.montant_mode_auto", { defaultValue: "Calcul automatique du montant fret" })}
                    </Label>
                    <p className="text-[11px] text-muted-foreground">
                      {t("colis.montant_mode_auto_desc", {
                        defaultValue: "Montant fret = pourcentage perçu × valeur marchandise.",
                      })}
                    </p>
                  </div>
                  <Switch
                    checked={montantMode === "auto"}
                    onCheckedChange={(checked) => setMontantMode(checked ? "auto" : "manuel")}
                  />
                </div>

                {montantMode === "auto" ? (
                  <div className="space-y-1.5">
                    <Label>{t("colis.pourcentage_percu", { defaultValue: "Pourcentage perçu (%)" })}</Label>
                    <Input
                      type="number"
                      min={0}
                      max={100}
                      step="0.1"
                      value={pourcentagePercu}
                      onChange={(e) => setPourcentagePercu(e.target.value)}
                      placeholder={t("colis.pourcentage_percu_placeholder", { defaultValue: "Ex: 10" })}
                    />
                  </div>
                ) : null}

                <div className="space-y-1.5">
                  <Label>{t("colis.montant", { defaultValue: "Montant fret (XOF)" })}</Label>
                  <Input
                    type="number"
                    min={0}
                    value={montantFret}
                    onChange={(e) => setMontantFret(e.target.value)}
                    disabled={montantMode === "auto"}
                    className={montantMode === "auto" ? "bg-muted" : undefined}
                  />
                  {prixMinSuggere != null ? (
                    <p
                      className={cn(
                        "text-xs",
                        (Number(montantFret) || 0) < prixMinSuggere
                          ? "text-destructive"
                          : "text-muted-foreground",
                      )}
                    >
                      {t("colis.prix_min_hint", {
                        defaultValue: `Prix minimum requis pour cette nature : ${prixMinSuggere.toLocaleString()} XOF`,
                        amount: prixMinSuggere.toLocaleString(),
                      })}
                    </p>
                  ) : null}
                  <p className="text-xs text-muted-foreground">
                    {t("colis.valeur_marchandise_hint", {
                      defaultValue:
                        "La valeur marchandise sert de base au remboursement en cas de perte et figure sur le reçu — elle pilote aussi le montant fret en mode automatique.",
                    })}
                  </p>
                </div>
              </div>

              <Button className="w-full cursor-pointer" disabled={saving} onClick={() => void handleRegister()}>
                {saving ? "…" : t("colis.register_btn", { defaultValue: "Enregistrer & encaisser" })}
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="suivi" className="space-y-3 mt-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            <Select value={filterStatut} onValueChange={(v) => setFilterStatut(v as ColisStatut | "all")}>
              <SelectTrigger><SelectValue placeholder="Statut" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Tous les statuts</SelectItem>
                {(Object.keys(COLIS_STATUT_LABELS) as ColisStatut[]).map((s) => (
                  <SelectItem key={s} value={s}>{COLIS_STATUT_LABELS[s]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={filterGareDepart} onValueChange={setFilterGareDepart}>
              <SelectTrigger><SelectValue placeholder="Gare de départ" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Toutes gares de départ</SelectItem>
                {suiviGaresDepart.map((gare) => (
                  <SelectItem key={gare} value={gare}>{gare}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={filterGareDest} onValueChange={setFilterGareDest}>
              <SelectTrigger><SelectValue placeholder="Gare d'arrivée" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Toutes gares d'arrivée</SelectItem>
                {suiviGaresDest.map((gare) => (
                  <SelectItem key={gare} value={gare}>{gare}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={filterBus} onValueChange={setFilterBus}>
              <SelectTrigger><SelectValue placeholder="Bus du convoi" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Tous les bus</SelectItem>
                {suiviBuses.map((plate) => (
                  <SelectItem key={plate} value={plate}>{plate}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              value={filterExpediteur}
              onChange={(e) => setFilterExpediteur(e.target.value)}
              placeholder={t("colis.filter_expediteur", { defaultValue: "Expéditeur (nom ou tél.)" })}
            />
            <Input
              value={filterDestinataire}
              onChange={(e) => setFilterDestinataire(e.target.value)}
              placeholder={t("colis.filter_destinataire", { defaultValue: "Destinataire (nom ou tél.)" })}
            />
            <Input
              value={filterReference}
              onChange={(e) => setFilterReference(e.target.value)}
              placeholder={t("colis.filter_reference", { defaultValue: "N° de colis (CL-… ou id)" })}
            />
          </div>
          {(filterStatut !== "all" || filterGareDepart !== "all" || filterGareDest !== "all" || filterBus !== "all" || filterExpediteur || filterDestinataire || filterReference) ? (
            <div className="flex items-center justify-between text-xs text-muted-foreground">
              <span>{filteredRows.length} colis correspondant(s)</span>
              <Button
                size="sm"
                variant="ghost"
                className="h-7 text-xs cursor-pointer"
                onClick={() => {
                  setFilterStatut("all");
                  setFilterGareDepart("all");
                  setFilterGareDest("all");
                  setFilterBus("all");
                  setFilterExpediteur("");
                  setFilterDestinataire("");
                  setFilterReference("");
                }}
              >
                {t("colis.filter_reset", { defaultValue: "Réinitialiser les filtres" })}
              </Button>
            </div>
          ) : null}

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
                    {row.busPlateNumber ? (
                      <p className="text-xs text-muted-foreground">
                        {t("colis.bus_assigned", { defaultValue: "Bus" })} : {row.busPlateNumber}
                      </p>
                    ) : null}
                    {next === "charge" && buses.length > 0 ? (
                      <select
                        className="h-8 w-full max-w-[220px] rounded-md border bg-transparent px-2 text-xs"
                        value={busSelections[row.id] ?? ""}
                        onChange={(e) =>
                          setBusSelections((prev) => ({ ...prev, [row.id]: e.target.value }))
                        }
                      >
                        <option value="">
                          {t("colis.bus_placeholder", { defaultValue: "Bus du convoi (optionnel)" })}
                        </option>
                        {buses.map((bus) => (
                          <option key={bus.id} value={bus.id}>
                            {bus.plateNumber}
                            {bus.model ? ` — ${bus.model}` : ""}
                          </option>
                        ))}
                      </select>
                    ) : null}
                    <div className="flex gap-2 flex-wrap">
                      {next && next !== "livre" ? (
                        <Button size="sm" variant="secondary" className="cursor-pointer gap-1" onClick={() => void handleAdvanceStatus(row)}>
                          <TruckIcon className="w-3.5 h-3.5" />
                          → {COLIS_STATUT_LABELS[next]}
                        </Button>
                      ) : null}
                      <Button size="sm" variant="outline" className="cursor-pointer gap-1" onClick={() => void handleShowReceipt(row.id)}>
                        <PrinterIcon className="w-3.5 h-3.5" /> Reçu
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="cursor-pointer gap-1 border-[#25D366]/50 text-[#128C7E] hover:bg-[#25D366]/10"
                        onClick={() => handleColisWhatsApp(row, "expediteur")}
                      >
                        <MessageCircleIcon className="w-3.5 h-3.5" /> Exp.
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="cursor-pointer gap-1 border-[#25D366]/50 text-[#128C7E] hover:bg-[#25D366]/10"
                        onClick={() => handleColisWhatsApp(row, "destinataire")}
                      >
                        <MessageCircleIcon className="w-3.5 h-3.5" /> Dest.
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              );
            })
          )}
        </TabsContent>

        <TabsContent value="bordereau" className="space-y-4 mt-4">
          {companyId ? (
            <BordereauPanel
              companyId={companyId}
              gares={gares}
              buses={buses}
              defaultGareDepartId={cashGareId || gareDepartId || null}
              onColisChanged={() => void refreshListSilently()}
            />
          ) : null}
        </TabsContent>

        <TabsContent value="retrait" className="space-y-4 mt-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">
                {t("colis.pickup_title", { defaultValue: "Contrôle colis (scan)" })}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-xs text-muted-foreground">
                Scannez le QR ou la référence CL- pour faire avancer le colis : en soute → arrivé →
                remis au destinataire.
              </p>
              <ColisScanWorkflow onAdvanced={() => void load()} />
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
