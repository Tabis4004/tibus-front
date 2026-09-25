import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import { RouteIcon, PlusIcon, ArrowRightIcon, TagIcon, TrashIcon, MapPinIcon, XIcon } from "lucide-react";
import { errorMessage } from "@/lib/utils";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog.tsx";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  Empty,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  EmptyDescription,
  EmptyContent,
} from "@/components/ui/empty.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";
import {
  listOwnerRoutesSupabase,
  listOwnerRouteStationsSupabase,
  createOwnerRouteSupabase,
  setTrajetSchedulingActiveSupabase,
  deleteOwnerRouteSupabase,
  addOwnerRouteStopSupabase,
  removeOwnerRouteStopSupabase,
  type OwnerStopSegmentInput,
  type OwnerRouteOption,
  type OwnerStationOption,
} from "@/lib/supabase/owner-trips";

const routeSchema = z.object({
  originStationId: z.string().min(1, "Select origin"),
  destinationStationId: z.string().min(1, "Select destination"),
  price: z.coerce.number().min(1, "Price required"),
  kilometrage: z.coerce.number().min(1).optional(),
});
type RouteFormData = z.infer<typeof routeSchema>;

// Partagé par RouteDialog (aperçu du libellé le temps de créer l'itinéraire)
// et par le parent (construction de l'itinéraire minimal transmis à
// StopDialog juste après la création, voir onSaved ci-dessous).
function stationLabel(s: OwnerStationOption) {
  return `${s.name}${s.city ? ` (${s.city})` : ""}`;
}

function RouteDialog({
  stations,
  onClose,
  onSaved,
}: {
  stations: OwnerStationOption[];
  onClose: () => void;
  // Renvoie l'itinéraire tout juste créé (au lieu de rien) pour que le
  // parent puisse enchaîner directement sur l'ajout d'escales, sans que
  // l'utilisateur ait à rouvrir l'itinéraire depuis la liste.
  onSaved: (created: {
    id: string;
    originStationId: string;
    destinationStationId: string;
    price: number;
    kilometrage?: number;
  }) => void;
}) {
  const { t } = useTranslation("owner");
  const [saving, setSaving] = useState(false);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<RouteFormData>({
    resolver: zodResolver(routeSchema),
    defaultValues: {
      originStationId: "",
      destinationStationId: "",
      price: 5000,
      kilometrage: undefined,
    },
  });

  const originId = watch("originStationId");
  const destId = watch("destinationStationId");

  const onSubmit = async (data: RouteFormData) => {
    if (data.originStationId === data.destinationStationId) {
      toast.error(t("routes.same_error"));
      return;
    }
    setSaving(true);
    try {
      const routeId = await createOwnerRouteSupabase({
        originStationId: data.originStationId,
        destinationStationId: data.destinationStationId,
        price: data.price,
        kilometrage: data.kilometrage,
      });
      toast.success(t("routes.created"));
      onSaved({
        id: routeId,
        originStationId: data.originStationId,
        destinationStationId: data.destinationStationId,
        price: data.price,
        kilometrage: data.kilometrage,
      });
      onClose();
    } catch (err) {
      toast.error(errorMessage(err, t("routes.create_error")));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>{t("routes.create_title")}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          <div className="space-y-1.5">
            <Label>{t("routes.origin")}</Label>
            <Select value={originId} onValueChange={(v) => setValue("originStationId", v)}>
              <SelectTrigger>
                <SelectValue placeholder={t("routes.select_origin")} />
              </SelectTrigger>
              <SelectContent>
                {stations.map((s) => (
                  <SelectItem key={s.id} value={s.id}>
                    {stationLabel(s)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.originStationId && (
              <p className="text-xs text-destructive">{errors.originStationId.message}</p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label>{t("routes.destination")}</Label>
            <Select
              value={destId}
              onValueChange={(v) => setValue("destinationStationId", v)}
            >
              <SelectTrigger>
                <SelectValue placeholder={t("routes.select_dest")} />
              </SelectTrigger>
              <SelectContent>
                {stations
                  .filter((s) => s.id !== originId)
                  .map((s) => (
                    <SelectItem key={s.id} value={s.id}>
                      {stationLabel(s)}
                    </SelectItem>
                  ))}
              </SelectContent>
            </Select>
            {errors.destinationStationId && (
              <p className="text-xs text-destructive">
                {errors.destinationStationId.message}
              </p>
            )}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>{t("labels.price", { ns: "common", defaultValue: "Prix" })}</Label>
              <Input type="number" min={1} {...register("price")} />
              {errors.price && (
                <p className="text-xs text-destructive">{errors.price.message}</p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label>{t("routes.km", { defaultValue: "Km" })}</Label>
              <Input type="number" min={1} {...register("kilometrage")} />
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>
              {t("buttons.cancel", { ns: "common" })}
            </Button>
            <Button type="submit" disabled={saving}>
              {saving ? t("routes.creating") : t("routes.create_btn")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function StopDialog({
  route,
  stations,
  appUserId,
  companyId,
  onClose,
  onSaved,
}: {
  route: OwnerRouteOption;
  stations: OwnerStationOption[];
  // Pour se rafraîchir soi-même après chaque escale ajoutée (voir submit
  // ci-dessous), sans dépendre d'un aller-retour par le parent.
  appUserId: string | null | undefined;
  companyId: string | null | undefined;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t } = useTranslation("owner");
  const [saving, setSaving] = useState(false);
  const [gareId, setGareId] = useState("");
  // Copie locale de l'itinéraire, mise à jour après chaque escale ajoutée
  // (voir submit) pour permettre d'en enchaîner plusieurs à la suite sans
  // fermer la boîte de dialogue — c'est ça qui manquait à la création.
  const [currentRoute, setCurrentRoute] = useState(route);
  const [addedCount, setAddedCount] = useState(0);
  // Ordre actuel de l'itinéraire : départ, escales existantes, arrivée.
  const ordered = [
    { gareId: currentRoute.originId, name: currentRoute.originName },
    ...currentRoute.stops.map((s) => ({ gareId: s.gareId, name: s.name })),
    { gareId: currentRoute.destId, name: currentRoute.destName },
  ];
  // Position = place de la nouvelle escale parmi les escales (1 = juste après le départ).
  const [position, setPosition] = useState(1);
  const [values, setValues] = useState<Record<string, { price: string; km: string }>>({});

  const candidates = stations.filter((s) => !ordered.some((o) => o.gareId === s.id));
  const chosen = stations.find((s) => s.id === gareId);
  const newName = chosen?.name ?? t("routes.new_stop", { defaultValue: "Nouvelle escale" });

  const setValue = (id: string, field: "price" | "km", v: string) =>
    setValues((prev) => ({
      ...prev,
      [id]: { price: prev[id]?.price ?? "", km: prev[id]?.km ?? "", [field]: v },
    }));

  const submit = async () => {
    if (!gareId) {
      toast.error(t("routes.stop_select_error", { defaultValue: "Choisissez une gare" }));
      return;
    }
    const segments: OwnerStopSegmentInput[] = [];
    for (let i = 0; i < ordered.length; i++) {
      const other = ordered[i];
      const price = Number(values[other.gareId]?.price);
      const kmRaw = values[other.gareId]?.km;
      if (!values[other.gareId]?.price || !Number.isFinite(price) || price < 0) {
        toast.error(
          t("routes.stop_price_error", { defaultValue: "Renseignez un prix pour chaque segment" }),
        );
        return;
      }
      const before = i < position; // gare existante située avant la nouvelle escale
      segments.push({
        fromGareId: before ? other.gareId : gareId,
        toGareId: before ? gareId : other.gareId,
        price,
        kilometrage: kmRaw ? Number(kmRaw) : null,
      });
    }
    setSaving(true);
    try {
      await addOwnerRouteStopSupabase({ trajetId: currentRoute.id, gareId, position, segments });
      toast.success(t("routes.stop_added", { defaultValue: "Escale ajoutée" }));
      onSaved(); // rafraîchit la liste en arrière-plan (carte de l'itinéraire)

      // On reste ouvert et on se recharge soi-même pour permettre d'enchaîner
      // l'escale suivante immédiatement (prix/segments recalculés par rapport
      // à TOUTES les gares déjà présentes, escale qu'on vient d'ajouter comprise) —
      // c'est ce qui manquait pour ajouter plusieurs escales à la création.
      if (appUserId && companyId) {
        const list = await listOwnerRoutesSupabase(appUserId, companyId);
        const updated = list.find((r) => r.id === currentRoute.id);
        if (updated) {
          setCurrentRoute(updated);
          setAddedCount((n) => n + 1);
          setGareId("");
          setValues({});
          setPosition(1);
        } else {
          onClose();
        }
      } else {
        onClose();
      }
    } catch (err) {
      toast.error(errorMessage(err, t("routes.stop_add_error", { defaultValue: "Impossible d'ajouter l'escale" })));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-md max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {t("routes.add_stop_title", { defaultValue: "Ajouter une escale" })}
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-1">
          <p className="text-xs text-muted-foreground">
            {currentRoute.originName} → {currentRoute.destName}
          </p>
          {currentRoute.stops.length > 0 && (
            <div className="flex flex-wrap items-center gap-1.5 text-xs">
              <MapPinIcon className="w-3 h-3 text-muted-foreground" />
              {currentRoute.stops.map((s) => (
                <span
                  key={s.gareId}
                  className="inline-flex items-center rounded-full bg-muted px-2 py-0.5"
                >
                  {s.name}
                </span>
              ))}
            </div>
          )}
          <div className="space-y-1.5">
            <Label>{t("routes.stop_station", { defaultValue: "Gare de l'escale" })}</Label>
            <Select value={gareId} onValueChange={setGareId}>
              <SelectTrigger>
                <SelectValue placeholder={t("routes.select_stop", { defaultValue: "Choisir une gare" })} />
              </SelectTrigger>
              <SelectContent>
                {candidates.map((s) => (
                  <SelectItem key={s.id} value={s.id}>
                    {s.name}
                    {s.city ? ` (${s.city})` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("routes.stop_position", { defaultValue: "Position" })}</Label>
            <Select value={String(position)} onValueChange={(v) => setPosition(Number(v))}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {ordered.slice(0, -1).map((o, i) => (
                  <SelectItem key={o.gareId} value={String(i + 1)}>
                    {t("routes.after", { defaultValue: "Après" })} {o.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>{t("routes.segment_prices", { defaultValue: "Prix par segment" })}</Label>
            {ordered.map((o, i) => {
              const before = i < position;
              return (
                <div key={o.gareId} className="grid grid-cols-[1fr_88px_64px] gap-2 items-center">
                  <span className="text-xs truncate">
                    {before ? `${o.name} → ${newName}` : `${newName} → ${o.name}`}
                  </span>
                  <Input
                    type="number"
                    min={0}
                    placeholder={t("labels.price", { ns: "common", defaultValue: "Prix" })}
                    value={values[o.gareId]?.price ?? ""}
                    onChange={(e) => setValue(o.gareId, "price", e.target.value)}
                  />
                  <Input
                    type="number"
                    min={0}
                    placeholder="Km"
                    value={values[o.gareId]?.km ?? ""}
                    onChange={(e) => setValue(o.gareId, "km", e.target.value)}
                  />
                </div>
              );
            })}
          </div>
        </div>
        <DialogFooter>
          <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>
            {addedCount > 0
              ? t("buttons.done", { ns: "common", defaultValue: "Terminé" })
              : t("buttons.cancel", { ns: "common" })}
          </Button>
          <Button type="button" onClick={() => void submit()} disabled={saving || !gareId}>
            {saving
              ? t("buttons.saving", { ns: "common" })
              : t("routes.add_stop_btn", { defaultValue: "Ajouter" })}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default function SupabaseRoutesManager() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const { companyId } = useOwnerCompany();
  const [routes, setRoutes] = useState<OwnerRouteOption[] | undefined>(undefined);
  const [stations, setStations] = useState<OwnerStationOption[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [togglingId, setTogglingId] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<OwnerRouteOption | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [stopRoute, setStopRoute] = useState<OwnerRouteOption | null>(null);
  const [removeStop, setRemoveStop] = useState<{ route: OwnerRouteOption; gareId: string; name: string } | null>(null);
  const [removingStop, setRemovingStop] = useState(false);

  const handleRemoveStop = async () => {
    if (!removeStop) return;
    setRemovingStop(true);
    try {
      await removeOwnerRouteStopSupabase(removeStop.route.id, removeStop.gareId);
      toast.success(t("routes.stop_removed", { defaultValue: "Escale supprimée" }));
      setRemoveStop(null);
      void loadData();
    } catch (err) {
      // Le serveur refuse si des billets sont déjà vendus sur cette escale.
      toast.error(errorMessage(err, t("routes.stop_remove_error", { defaultValue: "Impossible de supprimer l'escale" })));
    } finally {
      setRemovingStop(false);
    }
  };

  const loadData = useCallback(async () => {
    if (!appUserId || !companyId) return;
    setRoutes(undefined);
    try {
      const [routeList, stationList] = await Promise.all([
        listOwnerRoutesSupabase(appUserId, companyId),
        listOwnerRouteStationsSupabase(appUserId, companyId),
      ]);
      setRoutes(routeList);
      setStations(stationList);
    } catch (err) {
      toast.error(errorMessage(err, t("routes.create_error")));
      setRoutes([]);
    }
  }, [appUserId, companyId, t]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  useEffect(() => {
    const onRefresh = () => void loadData();
    window.addEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
  }, [loadData]);

  const handleSchedulingToggle = async (route: OwnerRouteOption, active: boolean) => {
    setTogglingId(route.id);
    try {
      await setTrajetSchedulingActiveSupabase(route.id, active);
      toast.success(active ? t("routes.activated") : t("routes.deactivated"));
      setRoutes((prev) =>
        (prev ?? []).map((item) =>
          item.id === route.id ? { ...item, isSchedulingActive: active } : item,
        ),
      );
    } catch (err) {
      toast.error(errorMessage(err, t("routes.update_error")));
    } finally {
      setTogglingId(null);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteOwnerRouteSupabase(deleteTarget.id);
      toast.success(t("routes.deleted"));
      setRoutes((prev) => (prev ?? []).filter((item) => item.id !== deleteTarget.id));
      setDeleteTarget(null);
    } catch (err) {
      // Le serveur refuse si des réservations sont rattachées à l'itinéraire
      // (voir migration delete_owner_route) : on affiche son message précis
      // plutôt que le message générique.
      toast.error(errorMessage(err, t("routes.delete_error")));
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("routes.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("routes.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setShowForm(true)} disabled={!stations.length}>
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("routes.create_btn")}
        </Button>
      </div>

      {routes === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-20 rounded-xl" />
          ))}
        </div>
      ) : routes.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <RouteIcon />
            </EmptyMedia>
            <EmptyTitle>{t("routes.no_routes")}</EmptyTitle>
            <EmptyDescription>{t("routes.no_routes_desc")}</EmptyDescription>
          </EmptyHeader>
          {stations.length > 0 && (
            <EmptyContent>
              <Button size="sm" onClick={() => setShowForm(true)}>
                {t("routes.create_first")}
              </Button>
            </EmptyContent>
          )}
        </Empty>
      ) : (
        <div className="space-y-3">
          {routes.map((route) => (
            <Card key={route.id}>
              <CardContent className="p-4 space-y-2">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-1.5 font-semibold text-sm flex-wrap min-w-0">
                    <span>{route.originName}</span>
                    <ArrowRightIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                    <span>{route.destName}</span>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <Label htmlFor={`scheduling-${route.id}`} className="text-[11px] text-muted-foreground">
                      {route.isSchedulingActive ? t("routes.scheduling_on") : t("routes.scheduling_off")}
                    </Label>
                    <Switch
                      id={`scheduling-${route.id}`}
                      checked={route.isSchedulingActive}
                      disabled={togglingId === route.id}
                      onCheckedChange={(checked) => void handleSchedulingToggle(route, checked)}
                    />
                    <Button
                      size="icon"
                      variant="ghost"
                      className="h-7 w-7 text-destructive hover:text-destructive"
                      onClick={() => setDeleteTarget(route)}
                    >
                      <TrashIcon className="w-3.5 h-3.5" />
                    </Button>
                  </div>
                </div>
                <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
                  <span>
                    {route.originCity} → {route.destCity}
                  </span>
                  <span className="flex items-center gap-1 font-semibold text-foreground">
                    <TagIcon className="w-3 h-3" />
                    {route.price.toLocaleString()} {route.currency}
                  </span>
                  {route.kilometrage != null && route.kilometrage > 0 && (
                    <span>{route.kilometrage} km</span>
                  )}
                </div>
                {route.stops.length > 0 && (
                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    <MapPinIcon className="w-3 h-3 text-muted-foreground" />
                    {route.stops.map((stop) => (
                      <span
                        key={stop.gareId}
                        className="inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5"
                      >
                        {stop.name}
                        <button
                          type="button"
                          aria-label={t("routes.remove_stop", { defaultValue: "Supprimer l'escale" })}
                          className="text-muted-foreground hover:text-destructive"
                          onClick={() =>
                            setRemoveStop({ route, gareId: stop.gareId, name: stop.name })
                          }
                        >
                          <XIcon className="w-3 h-3" />
                        </button>
                      </span>
                    ))}
                  </div>
                )}
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 text-xs"
                  onClick={() => setStopRoute(route)}
                >
                  <PlusIcon className="w-3 h-3 mr-1" />
                  {t("routes.add_stop_title", { defaultValue: "Ajouter une escale" })}
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {showForm && (
        <RouteDialog
          stations={stations}
          onClose={() => setShowForm(false)}
          onSaved={(created) => {
            void loadData();
            setShowForm(false);
            // Enchaîne directement sur l'ajout d'escales : on n'a pas besoin
            // d'attendre loadData(), on construit l'itinéraire minimal à
            // partir de ce qu'on sait déjà (origine/destination choisies).
            const origin = stations.find((s) => s.id === created.originStationId);
            const dest = stations.find((s) => s.id === created.destinationStationId);
            setStopRoute({
              id: created.id,
              originId: created.originStationId,
              destId: created.destinationStationId,
              stops: [],
              originName: origin ? stationLabel(origin) : "",
              destName: dest ? stationLabel(dest) : "",
              originCity: origin?.city ?? "",
              destCity: dest?.city ?? "",
              price: created.price,
              currency: "",
              kilometrage: created.kilometrage ?? null,
              isSchedulingActive: true,
            });
          }}
        />
      )}

      {stopRoute && (
        <StopDialog
          route={stopRoute}
          stations={stations}
          appUserId={appUserId}
          companyId={companyId}
          onClose={() => setStopRoute(null)}
          onSaved={() => void loadData()}
        />
      )}

      <AlertDialog open={!!removeStop} onOpenChange={(open) => !open && setRemoveStop(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {t("routes.remove_stop_confirm", { defaultValue: "Supprimer cette escale ?" })}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {removeStop?.name} —{" "}
              {t("routes.remove_stop_desc", {
                defaultValue: "Les segments et prix liés à cette escale seront supprimés.",
              })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={removingStop}>
              {t("buttons.cancel", { ns: "common" })}
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={handleRemoveStop}
              disabled={removingStop}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {t("buttons.delete", { ns: "common" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={!!deleteTarget} onOpenChange={(open) => !open && setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("routes.delete_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>{t("routes.delete_desc")}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>
              {t("buttons.cancel", { ns: "common" })}
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={deleting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {t("buttons.delete", { ns: "common" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
