import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { format } from "date-fns";
import {
  ArrowLeftIcon,
  ClipboardListIcon,
  LockIcon,
  PlusIcon,
  PrinterIcon,
  Trash2Icon,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import QrScanner from "@/pages/verify/_components/QrScanner.tsx";
import { supabaseErrorMessage } from "@/lib/supabase/errors";
import {
  COLIS_STATUT_LABELS,
  resolveColisRetraitCodeSupabase,
  sendColisSmsSupabase,
  type ColisAutonomeRow,
  type ColisBusOption,
  type ColisSmsPayload,
  type ColisStatut,
} from "@/lib/supabase/colis-autonomes.ts";
import {
  addColisToBordereauSupabase,
  closeBordereauSupabase,
  createBordereauSupabase,
  getBordereauSupabase,
  listBordereauxSupabase,
  listColisDisponiblesBordereauSupabase,
  removeColisFromBordereauSupabase,
  type BordereauDetail,
  type BordereauListRow,
} from "@/lib/supabase/bordereaux.ts";
import { exportBordereauPDF } from "@/lib/colis-manifest-export.ts";
import { getCompanyColisSettingsSupabase, type ColisReportConfig } from "@/lib/supabase/colis-autonomes.ts";

type GareOption = { id: string; name: string };

async function maybeSendChargeSms(colisId: string, statut: ColisStatut, sms: ColisSmsPayload) {
  if (!sms.send || !sms.message) return;
  const phones = [sms.expediteurPhone, sms.destinatairePhone].filter(Boolean) as string[];
  if (!phones.length) return;
  try {
    await sendColisSmsSupabase({ colisId, statut, message: sms.message, phones });
  } catch {
    // SMS optionnel — le colis est bien sur le bordereau.
  }
}

// Bordereau de livraison : créé manuellement, rempli en scannant les colis
// embarqués dans le bus (chaque scan passe le colis « chargé » + SMS).
export default function BordereauPanel({
  companyId,
  gares,
  buses,
  defaultGareDepartId,
  onColisChanged,
}: {
  companyId: string;
  gares: GareOption[];
  buses: ColisBusOption[];
  defaultGareDepartId?: string | null;
  onColisChanged?: () => void;
}) {
  const { t } = useTranslation("seller");
  const [list, setList] = useState<BordereauListRow[] | undefined>(undefined);
  const [detail, setDetail] = useState<BordereauDetail | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [creating, setCreating] = useState(false);
  const [gareDepartId, setGareDepartId] = useState(defaultGareDepartId ?? "");
  const [gareDestId, setGareDestId] = useState("");
  const [busId, setBusId] = useState("");
  const [manualRef, setManualRef] = useState("");
  const [adding, setAdding] = useState(false);
  const [addingId, setAddingId] = useState<string | null>(null);
  const [closing, setClosing] = useState(false);
  const [lastScan, setLastScan] = useState("");
  const [available, setAvailable] = useState<ColisAutonomeRow[] | undefined>(undefined);
  // Visibilité rapport bordereau (report entier + champs sensibles, ex.
  // montant global) configurée par l'owner — ColisFormBuilderPanel.tsx.
  const [bordereauReportConfig, setBordereauReportConfig] = useState<ColisReportConfig>({
    enabled: true,
    hiddenFields: [],
  });

  useEffect(() => {
    void getCompanyColisSettingsSupabase(companyId)
      .then((settings) => setBordereauReportConfig(settings.uiConfig.reports.bordereau))
      .catch(() => {});
  }, [companyId]);

  const loadList = useCallback(() => {
    setList(undefined);
    void listBordereauxSupabase(companyId)
      .then(setList)
      .catch((err) => {
        toast.error(supabaseErrorMessage(err, "Chargement des bordereaux impossible"));
        setList([]);
      });
  }, [companyId]);

  useEffect(() => {
    loadList();
  }, [loadList]);

  const openDetail = async (id: string) => {
    try {
      setDetail(await getBordereauSupabase(id));
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Bordereau introuvable"));
    }
  };

  // Colis déjà enregistrés à la gare de départ (et destination, si fixée)
  // du bordereau, pas encore livrés ni sur un autre bordereau ouvert —
  // alternative au scan / à la saisie manuelle, en un clic.
  const loadAvailable = useCallback((bordereauId: string) => {
    setAvailable(undefined);
    void listColisDisponiblesBordereauSupabase(bordereauId)
      .then(setAvailable)
      .catch((err) => {
        toast.error(supabaseErrorMessage(err, "Chargement des colis disponibles impossible"));
        setAvailable([]);
      });
  }, []);

  useEffect(() => {
    if (detail && detail.statut === "ouvert") {
      loadAvailable(detail.id);
    } else {
      setAvailable(undefined);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detail?.id, detail?.statut]);

  const handleCreate = async () => {
    if (!gareDepartId) {
      toast.error("Choisissez la gare de départ");
      return;
    }
    setCreating(true);
    try {
      const created = await createBordereauSupabase({
        companyId,
        gareDepartId,
        gareDestinationId: gareDestId || null,
        busId: busId || null,
      });
      toast.success(`Bordereau ${created.reference} créé — scannez les colis embarqués.`);
      setShowCreate(false);
      setDetail(created);
      loadList();
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Création impossible"));
    } finally {
      setCreating(false);
    }
  };

  // Cœur commun scan / saisie manuelle / bouton "Ajouter" de la liste : le
  // colis est déjà identifié (colisId), il ne reste qu'à l'ajouter et
  // rafraîchir le détail + la liste des colis encore disponibles.
  const finalizeAddColis = useCallback(
    async (colisId: string) => {
      if (!detail) return;
      const result = await addColisToBordereauSupabase(detail.id, colisId);
      void maybeSendChargeSms(result.id, result.statutColis, result.sms);
      const next = await getBordereauSupabase(detail.id);
      setDetail(next);
      loadAvailable(detail.id);
      onColisChanged?.();
      toast.success(`Colis ajouté (${next.colis.length} sur le bordereau)`);
    },
    [detail, onColisChanged, loadAvailable],
  );

  const addColis = useCallback(
    async (raw: string) => {
      if (!detail || detail.statut !== "ouvert" || adding) return;
      const code = raw.trim();
      if (!code || code === lastScan) return;
      setLastScan(code);
      setAdding(true);
      try {
        const colisId = await resolveColisRetraitCodeSupabase(code);
        if (!colisId) throw new Error("Colis introuvable — scannez le QR du reçu ou saisissez CL-XXXXXXXX");
        await finalizeAddColis(colisId);
        setManualRef("");
      } catch (err) {
        toast.error(supabaseErrorMessage(err, "Ajout impossible"));
      } finally {
        setAdding(false);
        window.setTimeout(() => setLastScan(""), 2500);
      }
    },
    [detail, adding, lastScan, finalizeAddColis],
  );

  // Ajout direct depuis la liste des colis disponibles (sans scan ni saisie).
  const addColisDirect = useCallback(
    async (colisId: string) => {
      if (!detail || detail.statut !== "ouvert" || addingId) return;
      setAddingId(colisId);
      try {
        await finalizeAddColis(colisId);
      } catch (err) {
        toast.error(supabaseErrorMessage(err, "Ajout impossible"));
      } finally {
        setAddingId(null);
      }
    },
    [detail, addingId, finalizeAddColis],
  );

  const handleRemove = async (colisId: string) => {
    if (!detail) return;
    try {
      await removeColisFromBordereauSupabase(detail.id, colisId);
      setDetail(await getBordereauSupabase(detail.id));
      loadAvailable(detail.id);
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Retrait impossible"));
    }
  };

  const handleClose = async () => {
    if (!detail) return;
    setClosing(true);
    try {
      const closed = await closeBordereauSupabase(detail.id);
      setDetail(closed);
      loadList();
      toast.success(`Bordereau ${closed.reference} clôturé.`);
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Clôture impossible"));
    } finally {
      setClosing(false);
    }
  };

  // ── Vue détail (scan + liste) ─────────────────────────────────────────
  if (detail) {
    const isOpen = detail.statut === "ouvert";
    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <Button
            size="sm"
            variant="ghost"
            className="cursor-pointer"
            onClick={() => {
              setDetail(null);
              loadList();
            }}
          >
            <ArrowLeftIcon className="w-4 h-4 mr-1" />
            {t("colis.bordereau_back", { defaultValue: "Bordereaux" })}
          </Button>
          <div className="flex items-center gap-2">
            <Badge variant={isOpen ? "default" : "secondary"}>
              {isOpen
                ? t("colis.bordereau_open", { defaultValue: "En cours" })
                : t("colis.bordereau_closed", { defaultValue: "Emballé" })}
            </Badge>
            {bordereauReportConfig.enabled ? (
              <Button
                size="sm"
                variant="outline"
                className="cursor-pointer gap-1"
                onClick={() => exportBordereauPDF(detail, { hiddenFields: bordereauReportConfig.hiddenFields })}
              >
                <PrinterIcon className="w-3.5 h-3.5" />
                {t("colis.bordereau_print", { defaultValue: "Imprimer" })}
              </Button>
            ) : null}
            {isOpen ? (
              <Button
                size="sm"
                className="cursor-pointer gap-1"
                disabled={closing || detail.colis.length === 0}
                onClick={() => void handleClose()}
              >
                <LockIcon className="w-3.5 h-3.5" />
                {t("colis.bordereau_close", { defaultValue: "Clôturer" })}
              </Button>
            ) : null}
          </div>
        </div>

        <Card>
          <CardContent className="p-4 space-y-1">
            <p className="font-bold">{detail.reference}</p>
            <p className="text-sm">
              {detail.gareDepart} → {detail.gareDestination ?? t("colis.bordereau_all_dest", { defaultValue: "toutes destinations" })}
              {detail.busPlateNumber ? ` · Bus ${detail.busPlateNumber}` : ""}
            </p>
            <p className="text-xs text-muted-foreground">
              {format(new Date(detail.createdAt), "dd/MM/yyyy HH:mm")} ·{" "}
              {detail.colis.length}{" "}
              {t("colis.bordereau_count", { defaultValue: "colis scannés" })}
            </p>
          </CardContent>
        </Card>

        {isOpen ? (
          <Card>
            <CardContent className="p-4 space-y-3">
              <p className="text-sm font-semibold">
                {t("colis.bordereau_scan_title", {
                  defaultValue: "Scannez le QR du reçu de chaque colis embarqué",
                })}
              </p>
              <QrScanner onScan={(payload) => void addColis(payload)} paused={adding} />
              <div className="flex gap-2">
                <Input
                  value={manualRef}
                  onChange={(e) => setManualRef(e.target.value)}
                  placeholder="CL-XXXXXXXX"
                  onKeyDown={(e) => {
                    if (e.key === "Enter") void addColis(manualRef);
                  }}
                />
                <Button
                  variant="secondary"
                  className="cursor-pointer"
                  disabled={adding || !manualRef.trim()}
                  onClick={() => void addColis(manualRef)}
                >
                  <PlusIcon className="w-4 h-4 mr-1" />
                  {t("colis.bordereau_add", { defaultValue: "Ajouter" })}
                </Button>
              </div>
            </CardContent>
          </Card>
        ) : null}

        {isOpen ? (
          <Card>
            <CardContent className="p-4 space-y-3">
              <p className="text-sm font-semibold">
                {t("colis.bordereau_available_title", {
                  defaultValue: "Colis en attente à cette gare — ajout en un clic",
                })}
              </p>
              {available === undefined ? (
                <Skeleton className="h-16 w-full" />
              ) : available.length === 0 ? (
                <p className="text-xs text-muted-foreground">
                  {t("colis.bordereau_available_empty", {
                    defaultValue: "Aucun colis en attente pour cette gare de départ / destination.",
                  })}
                </p>
              ) : (
                <div className="space-y-2">
                  {available.map((row) => (
                    <div
                      key={row.id}
                      className="flex items-start justify-between gap-3 rounded-md border p-2.5"
                    >
                      <div className="min-w-0 text-sm">
                        <p className="font-semibold">
                          CL-{row.id.slice(0, 8).toUpperCase()}
                          <span className="ml-2 font-normal text-muted-foreground">
                            {row.gareDepart} → {row.gareDestination}
                          </span>
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {row.nomExpediteur} ({row.telephoneExpediteur}) → {row.nomDestinataire} ({row.telephoneDestinataire})
                        </p>
                        <p className="text-xs">
                          {row.natures.join(", ")} · {row.nombrePieces} pièce(s)
                          {row.poidsKg != null ? ` · ${row.poidsKg} kg` : ""}
                        </p>
                      </div>
                      <Button
                        size="sm"
                        variant="secondary"
                        className="cursor-pointer gap-1 shrink-0"
                        disabled={Boolean(addingId) || adding}
                        onClick={() => void addColisDirect(row.id)}
                      >
                        <PlusIcon className="w-3.5 h-3.5" />
                        {addingId === row.id
                          ? "…"
                          : t("colis.bordereau_add", { defaultValue: "Ajouter" })}
                      </Button>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        ) : null}

        {detail.colis.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-6">
            {t("colis.bordereau_empty", { defaultValue: "Aucun colis scanné pour l'instant." })}
          </p>
        ) : (
          <div className="space-y-2">
            {detail.colis.map((row, index) => (
              <Card key={row.id}>
                <CardContent className="p-3 flex items-start justify-between gap-3">
                  <div className="min-w-0 text-sm">
                    <p className="font-semibold">
                      {index + 1}. CL-{row.id.slice(0, 8).toUpperCase()}
                      <span className="ml-2 font-normal text-muted-foreground">
                        {row.gareDepart} → {row.gareDestination}
                      </span>
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {row.nomExpediteur} ({row.telephoneExpediteur}) → {row.nomDestinataire} ({row.telephoneDestinataire})
                    </p>
                    <p className="text-xs">
                      {row.natures.join(", ")} · {row.nombrePieces} pièce(s)
                      {row.poidsKg != null ? ` · ${row.poidsKg} kg` : ""} ·{" "}
                      {row.montantFret.toLocaleString()} XOF
                    </p>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <Badge variant="secondary" className="text-[10px]">
                      {COLIS_STATUT_LABELS[row.statutColis]}
                    </Badge>
                    {isOpen ? (
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7 text-destructive hover:text-destructive cursor-pointer"
                        onClick={() => void handleRemove(row.id)}
                      >
                        <Trash2Icon className="w-3.5 h-3.5" />
                      </Button>
                    ) : null}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>
    );
  }

  // ── Liste + création ──────────────────────────────────────────────────
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          {t("colis.bordereau_desc", {
            defaultValue:
              "Créez un bordereau au chargement du bus, scannez les colis embarqués, puis imprimez-le pour le convoyage.",
          })}
        </p>
        <Button size="sm" className="cursor-pointer shrink-0" onClick={() => setShowCreate(true)}>
          <PlusIcon className="w-4 h-4 mr-1.5" />
          {t("colis.bordereau_create", { defaultValue: "Créer un bordereau" })}
        </Button>
      </div>

      {list === undefined ? (
        <Skeleton className="h-40 w-full" />
      ) : list.length === 0 ? (
        <div className="rounded-xl border p-8 text-center text-muted-foreground">
          <ClipboardListIcon className="w-10 h-10 mx-auto opacity-30 mb-2" />
          <p className="text-sm">
            {t("colis.bordereau_none", { defaultValue: "Aucun bordereau. Créez-en un au prochain chargement." })}
          </p>
        </div>
      ) : (
        list.map((row) => (
          <Card
            key={row.id}
            className="cursor-pointer hover:bg-muted/40 transition-colors"
            onClick={() => void openDetail(row.id)}
          >
            <CardContent className="p-4 flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="font-semibold text-sm">
                  {row.reference}
                  <span className="ml-2 font-normal text-muted-foreground">
                    {row.gareDepart} → {row.gareDestination ?? "toutes destinations"}
                  </span>
                </p>
                <p className="text-xs text-muted-foreground">
                  {format(new Date(row.createdAt), "dd/MM/yyyy HH:mm")}
                  {row.busPlateNumber ? ` · Bus ${row.busPlateNumber}` : ""} · {row.colisCount} colis
                </p>
              </div>
              <Badge variant={row.statut === "ouvert" ? "default" : "secondary"}>
                {row.statut === "ouvert"
                  ? t("colis.bordereau_open", { defaultValue: "En cours" })
                  : t("colis.bordereau_closed", { defaultValue: "Emballé" })}
              </Badge>
            </CardContent>
          </Card>
        ))
      )}

      {showCreate ? (
        <Dialog open onOpenChange={(open) => !open && !creating && setShowCreate(false)}>
          <DialogContent className="max-w-sm">
            <DialogHeader>
              <DialogTitle>
                {t("colis.bordereau_create", { defaultValue: "Créer un bordereau" })}
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-4 py-1">
              <div className="space-y-1.5">
                <Label>Gare de départ *</Label>
                <Select value={gareDepartId} onValueChange={setGareDepartId}>
                  <SelectTrigger>
                    <SelectValue placeholder="Choisir la gare" />
                  </SelectTrigger>
                  <SelectContent>
                    {gares.map((gare) => (
                      <SelectItem key={gare.id} value={gare.id}>{gare.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>Gare de destination (optionnel)</Label>
                <Select
                  value={gareDestId || "__all__"}
                  onValueChange={(v) => setGareDestId(v === "__all__" ? "" : v)}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__all__">Toutes destinations</SelectItem>
                    {gares
                      .filter((gare) => gare.id !== gareDepartId)
                      .map((gare) => (
                        <SelectItem key={gare.id} value={gare.id}>{gare.name}</SelectItem>
                      ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>Bus du convoi (optionnel)</Label>
                <Select
                  value={busId || "__none__"}
                  onValueChange={(v) => setBusId(v === "__none__" ? "" : v)}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">—</SelectItem>
                    {buses.map((bus) => (
                      <SelectItem key={bus.id} value={bus.id}>
                        {bus.plateNumber}{bus.model ? ` — ${bus.model}` : ""}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <DialogFooter>
              <Button variant="secondary" onClick={() => setShowCreate(false)} disabled={creating}>
                {t("buttons.cancel", { ns: "common" })}
              </Button>
              <Button onClick={() => void handleCreate()} disabled={creating || !gareDepartId}>
                {creating ? "…" : t("colis.bordereau_create_btn", { defaultValue: "Créer et scanner" })}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      ) : null}
    </div>
  );
}
