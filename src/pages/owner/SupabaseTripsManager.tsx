import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { format, parseISO } from "date-fns";
import { formatRouteOptionLabel, formatTripItineraryLabel } from "@/lib/trip-display.ts";
import { toast } from "sonner";
import {
  CalendarIcon,
  PlusIcon,
  PencilIcon,
  TrashIcon,
  ArrowRightIcon,
  BusIcon,
  ClockIcon,
  FileTextIcon,
  TagIcon,
  UsersIcon,
} from "lucide-react";
import { getTripManifestSupabase } from "@/lib/supabase/owner-reports";
import { exportTripManifestPDF } from "@/lib/trip-manifest-export";
import { errorMessage } from "@/lib/utils.ts";
import TripIncidentsDialog from "./_components/TripIncidentsDialog.tsx";
import {
  listTripIncidentCountsSupabase,
  type TripIncidentCount,
} from "@/lib/supabase/trip-incidents.ts";
import { MegaphoneIcon } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
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
  Empty,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  EmptyDescription,
  EmptyContent,
} from "@/components/ui/empty.tsx";
import { cn } from "@/lib/utils.ts";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";
import {
  listOwnerDeparturesSupabase,
  listOwnerRoutesSupabase,
  listOwnerBusesSupabase,
  createOwnerDepartureSupabase,
  updateOwnerDepartureSupabase,
  deleteOwnerDepartureSupabase,
  type OwnerDeparture,
  type OwnerRouteOption,
  type OwnerBusOption,
} from "@/lib/supabase/owner-trips";

const STATUS_STYLES: Record<string, string> = {
  scheduled:
    "bg-blue-100 text-blue-700 border-blue-200 dark:bg-blue-900/30 dark:text-blue-400",
  active:
    "bg-emerald-100 text-emerald-700 border-emerald-200 dark:bg-emerald-900/30 dark:text-emerald-400",
  completed: "bg-muted text-muted-foreground border-border",
};

const tripSchema = z.object({
  routeId: z.string().min(1, "Select a route"),
  busId: z.string().min(1, "Select a bus"),
  departureDate: z.string().min(1, "Select departure date"),
  departureTime: z.string().min(1, "Select departure time"),
  capacity: z.coerce.number().min(1, "Capacity required"),
});
type TripFormData = z.infer<typeof tripSchema>;

function StatusBadge({ status }: { status: string }) {
  return (
    <span
      className={cn(
        "text-[10px] font-semibold px-2 py-0.5 rounded-full border capitalize",
        STATUS_STYLES[status] ?? STATUS_STYLES.scheduled,
      )}
    >
      {status}
    </span>
  );
}

function TripFormDialog({
  trip,
  routes,
  buses,
  onClose,
  onSaved,
  appUserId,
  companyId,
}: {
  trip?: OwnerDeparture;
  routes: OwnerRouteOption[];
  buses: OwnerBusOption[];
  onClose: () => void;
  onSaved: () => void;
  appUserId: string;
  companyId: string;
}) {
  const { t } = useTranslation("owner");
  const [saving, setSaving] = useState(false);

  const existingDep = trip ? parseISO(trip.departureTime) : null;
  const selectedRoute = routes.find((r) => r.id === trip?.trajetId);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<TripFormData>({
    resolver: zodResolver(tripSchema),
    defaultValues: {
      routeId: trip?.trajetId ?? "",
      busId: trip?.bus?.id ?? "",
      departureDate: existingDep ? format(existingDep, "yyyy-MM-dd") : "",
      departureTime: existingDep ? format(existingDep, "HH:mm") : "",
      capacity: trip?.totalSeats ?? 45,
    },
  });

  const routeId = watch("routeId");
  const busId = watch("busId");
  const route = routes.find((r) => r.id === routeId);
  const bus = buses.find((b) => b.id === busId);

  useEffect(() => {
    if (bus && !trip) {
      setValue("capacity", bus.capacity);
    }
  }, [bus, trip, setValue]);

  const routeLabel = (r: OwnerRouteOption) =>
    formatRouteOptionLabel({
      originCity: r.originCity,
      originGare: r.originName,
      destCity: r.destCity,
      destGare: r.destName,
      price: r.price,
      currency: r.currency,
    });

  const onSubmit = async (data: TripFormData) => {
    const depISO = new Date(
      `${data.departureDate}T${data.departureTime}:00`,
    ).toISOString();

    if (new Date(depISO) <= new Date()) {
      toast.error("La date de départ doit être dans le futur");
      return;
    }

    setSaving(true);
    try {
      if (trip) {
        await updateOwnerDepartureSupabase({
          appUserId,
          companyId,
          reservationId: trip.id,
          departureIso: depISO,
          capacity: data.capacity,
          busId: data.busId,
          trajetId: data.routeId,
        });
        toast.success(t("trips.updated"));
      } else {
        await createOwnerDepartureSupabase({
          appUserId,
          companyId,
          trajetId: data.routeId,
          busId: data.busId,
          departureIso: depISO,
          capacity: data.capacity,
        });
        toast.success(t("trips.scheduled"));
      }
      onSaved();
      onClose();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : t("trips.save_error"),
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {trip ? t("trips.edit_trip") : t("trips.schedule_new")}
          </DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          <div className="space-y-1.5">
            <Label>{t("labels.route", { ns: "common" })}</Label>
            <Select
              value={routeId}
              onValueChange={(v) => setValue("routeId", v)}
            >
              <SelectTrigger>
                <SelectValue placeholder={t("trips.select_route")} />
              </SelectTrigger>
              <SelectContent>
                {routes.map((r) => (
                  <SelectItem key={r.id} value={r.id}>
                    {routeLabel(r)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.routeId && (
              <p className="text-xs text-destructive">{errors.routeId.message}</p>
            )}
          </div>

          <div className="space-y-1.5">
            <Label>{t("labels.bus", { ns: "common" })}</Label>
            <Select value={busId} onValueChange={(v) => setValue("busId", v)}>
              <SelectTrigger>
                <SelectValue placeholder={t("trips.select_bus")} />
              </SelectTrigger>
              <SelectContent>
                {buses.map((b) => (
                  <SelectItem key={b.id} value={b.id}>
                    {b.name} · {b.plateNumber} · {b.capacity}{" "}
                    {t("labels.seats", { ns: "common" })}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.busId && (
              <p className="text-xs text-destructive">{errors.busId.message}</p>
            )}
          </div>

          <div className="space-y-1.5">
            <Label>{t("labels.departure", { ns: "common" })}</Label>
            <div className="grid grid-cols-2 gap-2">
              <Input type="date" {...register("departureDate")} />
              <Input type="time" {...register("departureTime")} />
            </div>
            {(errors.departureDate || errors.departureTime) && (
              <p className="text-xs text-destructive">{t("trips.dep_required")}</p>
            )}
          </div>

          <div className="space-y-1.5">
            <Label>{t("labels.seats", { ns: "common" })}</Label>
            <Input type="number" min={1} {...register("capacity")} />
            {errors.capacity && (
              <p className="text-xs text-destructive">{errors.capacity.message}</p>
            )}
          </div>

          {(route ?? selectedRoute) && (
            <p className="text-xs text-muted-foreground">
              Prix par place :{" "}
              <span className="font-semibold text-foreground">
                {(route ?? selectedRoute)!.price.toLocaleString()}{" "}
                {(route ?? selectedRoute)!.currency}
              </span>{" "}
              (défini sur le trajet)
            </p>
          )}

          <DialogFooter>
            <Button
              type="button"
              variant="secondary"
              onClick={onClose}
              disabled={saving}
            >
              {t("buttons.cancel", { ns: "common" })}
            </Button>
            <Button type="submit" disabled={saving}>
              {saving
                ? t("buttons.saving", { ns: "common" })
                : trip
                  ? t("company.save_btn")
                  : t("trips.schedule")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

const FILTER_TABS = ["all", "scheduled", "active", "completed"] as const;
type FilterTab = (typeof FILTER_TABS)[number];

export default function SupabaseTripsManager() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const { companyId } = useOwnerCompany();
  const [trips, setTrips] = useState<OwnerDeparture[] | undefined>(undefined);
  const [routes, setRoutes] = useState<OwnerRouteOption[]>([]);
  const [buses, setBuses] = useState<OwnerBusOption[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editTrip, setEditTrip] = useState<OwnerDeparture | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);
  const [manifestBusyId, setManifestBusyId] = useState<string | null>(null);
  const [incidentCounts, setIncidentCounts] = useState<Map<string, TripIncidentCount>>(new Map());
  const [incidentTrip, setIncidentTrip] = useState<{ id: string; label: string } | null>(null);

  const loadIncidentCounts = async () => {
    if (!companyId) return;
    try {
      setIncidentCounts(await listTripIncidentCountsSupabase(companyId));
    } catch {
      setIncidentCounts(new Map());
    }
  };

  useEffect(() => {
    void loadIncidentCounts();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [companyId]);

  const handleManifest = async (tripId: string) => {
    if (!appUserId) return;
    setManifestBusyId(tripId);
    try {
      const manifest = await getTripManifestSupabase(tripId, appUserId);
      exportTripManifestPDF(manifest);
    } catch (err) {
      toast.error(
        errorMessage(err, t("trips.manifest_error", { defaultValue: "Manifeste indisponible pour ce voyage." })),
      );
    } finally {
      setManifestBusyId(null);
    }
  };
  const [filter, setFilter] = useState<FilterTab>("all");

  const loadData = useCallback(async () => {
    if (!appUserId || !companyId) return;
    setTrips(undefined);
    try {
      const [departures, routeList, busList] = await Promise.all([
        listOwnerDeparturesSupabase(appUserId, companyId),
        listOwnerRoutesSupabase(appUserId, companyId, { schedulingOnly: true }),
        listOwnerBusesSupabase(appUserId, companyId),
      ]);
      setTrips(departures);
      setRoutes(routeList);
      setBuses(busList);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Erreur de chargement",
      );
      setTrips([]);
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

  const filteredTrips = (trips ?? []).filter(
    (trip) => filter === "all" || trip.status === filter,
  );

  const handleDelete = async () => {
    if (!deleteId || !appUserId) return;
    try {
      await deleteOwnerDepartureSupabase(appUserId, deleteId, companyId);
      toast.success(t("trips.deleted"));
      void loadData();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : t("trips.delete_error"),
      );
    } finally {
      setDeleteId(null);
    }
  };

  const filterLabel = (tab: FilterTab) => {
    const map: Record<FilterTab, string> = {
      all: t("trips.filter.all"),
      scheduled: t("trips.filter.scheduled"),
      active: t("trips.filter.active"),
      completed: t("trips.filter.completed"),
    };
    return map[tab];
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">
            {t("trips.title")}
          </h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("trips.desc")}</p>
        </div>
        <Button
          size="sm"
          onClick={() => setShowForm(true)}
          className="cursor-pointer"
          disabled={!routes.length || !buses.length}
        >
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("trips.schedule")}
        </Button>
      </div>

      <div className="flex gap-1.5 overflow-x-auto pb-1 scrollbar-thin">
        {FILTER_TABS.map((tab) => (
          <button
            key={tab}
            onClick={() => setFilter(tab)}
            className={cn(
              "px-3 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-colors cursor-pointer",
              filter === tab
                ? "bg-primary text-primary-foreground"
                : "bg-muted text-muted-foreground hover:bg-muted/80",
            )}
          >
            {filterLabel(tab)}
            {tab !== "all" && trips && (
              <span className="ml-1 opacity-70">
                ({trips.filter((trip) => trip.status === tab).length})
              </span>
            )}
          </button>
        ))}
      </div>

      {trips === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-28 rounded-xl" />
          ))}
        </div>
      ) : filteredTrips.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <CalendarIcon />
            </EmptyMedia>
            <EmptyTitle>
              {t("trips.no_trips", { filter: filter === "all" ? "" : filter })}
            </EmptyTitle>
            <EmptyDescription>
              {filter === "all"
                ? t("trips.no_trips_all")
                : t("trips.no_trips_filter", { filter })}
            </EmptyDescription>
          </EmptyHeader>
          {filter === "all" && routes.length > 0 && buses.length > 0 && (
            <EmptyContent>
              <Button size="sm" onClick={() => setShowForm(true)}>
                <PlusIcon className="w-4 h-4 mr-1.5" /> {t("trips.schedule_first")}
              </Button>
            </EmptyContent>
          )}
        </Empty>
      ) : (
        <div className="space-y-3">
          {filteredTrips.map((trip) => (
            <Card
              key={trip.id}
              className={cn(
                "transition-all",
                trip.status === "completed" && "opacity-70",
              )}
            >
              <CardContent className="p-4 space-y-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="font-semibold text-sm flex-wrap">
                    {trip.origin && trip.destination ? (
                      <p className="leading-snug">
                        {formatTripItineraryLabel({
                          originCity: trip.origin.city,
                          originGare: trip.origin.name,
                          destinationCity: trip.destination.city,
                          destinationGare: trip.destination.name,
                          departureTime: trip.departureTime,
                          arrivalTime: trip.arrivalTime,
                          priceAmount: trip.priceAmount,
                          currency: trip.currency,
                        })}
                      </p>
                    ) : (
                      <span className="inline-flex items-center gap-1.5">
                        <span>Unknown</span>
                        <ArrowRightIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                        <span>Unknown</span>
                      </span>
                    )}
                  </div>
                  <StatusBadge status={trip.status} />
                </div>

                <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
                  <span className="flex items-center gap-1">
                    <ClockIcon className="w-3 h-3" />
                    {format(parseISO(trip.departureTime), "dd MMM yyyy, HH:mm")}
                    <span className="text-foreground/40">→</span>
                    {format(parseISO(trip.arrivalTime), "HH:mm")}
                  </span>
                  <span className="flex items-center gap-1">
                    <BusIcon className="w-3 h-3" />
                    {trip.bus?.name ?? "—"}
                    {trip.bus?.plateNumber ? ` (${trip.bus.plateNumber})` : ""}
                  </span>
                  <span className="flex items-center gap-1">
                    <UsersIcon className="w-3 h-3" />
                    {trip.seatsAvailable}/{trip.totalSeats}{" "}
                    {t("labels.seats", { ns: "common" })}
                  </span>
                  <span className="flex items-center gap-1 font-semibold text-foreground">
                    <TagIcon className="w-3 h-3" />
                    {trip.currency} {trip.priceAmount.toLocaleString()}
                  </span>
                </div>

                <div className="flex items-center gap-2 pt-1">
                  <Button
                    size="sm"
                    variant="ghost"
                    className="h-7 text-xs cursor-pointer"
                    onClick={() => setEditTrip(trip)}
                    disabled={
                      trip.status === "completed" || trip.seatsBooked > 0
                    }
                  >
                    <PencilIcon className="w-3 h-3 mr-1" />{" "}
                    {t("buttons.edit", { ns: "common" })}
                  </Button>

                  <Button
                    size="sm"
                    variant="ghost"
                    className="h-7 text-xs cursor-pointer"
                    disabled={manifestBusyId === trip.id}
                    onClick={() => void handleManifest(trip.id)}
                  >
                    <FileTextIcon className="w-3 h-3 mr-1" />{" "}
                    {t("trips.manifest_btn", { defaultValue: "Manifeste" })}
                  </Button>

                  <Button
                    size="sm"
                    variant="ghost"
                    className="h-7 text-xs cursor-pointer"
                    onClick={() =>
                      setIncidentTrip({
                        id: trip.id,
                        label:
                          trip.origin && trip.destination
                            ? `${trip.origin.city} → ${trip.destination.city} · ${format(parseISO(trip.departureTime), "dd/MM HH:mm")}`
                            : format(parseISO(trip.departureTime), "dd/MM HH:mm"),
                      })
                    }
                  >
                    <MegaphoneIcon className="w-3 h-3 mr-1" />{" "}
                    {t("trips.incidents_btn", { defaultValue: "Incidents" })}
                    {(incidentCounts.get(trip.id)?.total ?? 0) > 0 ? (
                      <span
                        className={cn(
                          "ml-1 rounded-full px-1.5 text-[10px] font-bold",
                          (incidentCounts.get(trip.id)?.nouveaux ?? 0) > 0
                            ? "bg-destructive text-destructive-foreground"
                            : "bg-muted text-muted-foreground",
                        )}
                      >
                        {incidentCounts.get(trip.id)?.total}
                      </span>
                    ) : null}
                  </Button>

                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7 ml-auto cursor-pointer text-destructive hover:text-destructive"
                    onClick={() => setDeleteId(trip.id)}
                    disabled={trip.seatsBooked > 0}
                  >
                    <TrashIcon className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {incidentTrip ? (
        <TripIncidentsDialog
          reservationId={incidentTrip.id}
          tripLabel={incidentTrip.label}
          onClose={() => {
            setIncidentTrip(null);
            void loadIncidentCounts();
          }}
        />
      ) : null}

      {(showForm || editTrip) && appUserId && companyId && (
        <TripFormDialog
          trip={editTrip ?? undefined}
          routes={routes}
          buses={buses}
          appUserId={appUserId}
          companyId={companyId}
          onClose={() => {
            setShowForm(false);
            setEditTrip(null);
          }}
          onSaved={() => void loadData()}
        />
      )}

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("trips.delete_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>{t("trips.delete_desc")}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>
              {t("buttons.cancel", { ns: "common" })}
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
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
