import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import {
  CalendarIcon, PlusIcon, PencilIcon, TrashIcon, ArrowRightIcon,
  BusIcon, ClockIcon, TagIcon, UsersIcon, ChevronDownIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from "@/components/ui/dialog.tsx";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select.tsx";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog.tsx";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from "@/components/ui/empty.tsx";
import { cn } from "@/lib/utils.ts";

// ─── Types ────────────────────────────────────────────────────────────────────
type RouteOption = {
  _id: Id<"routes">;
  origin: { name: string } | null;
  destination: { name: string } | null;
  originLoc: { city: string } | null;
  destLoc: { city: string } | null;
};
type BusOption = { _id: Id<"buses">; name: string; plateNumber: string; capacity: number };

const CURRENCIES = ["USD", "EUR", "GBP", "XAF", "NGN", "KES", "GHS", "ZAR", "ETB", "TZS"];

const STATUS_STYLES: Record<string, string> = {
  scheduled: "bg-blue-100 text-blue-700 border-blue-200 dark:bg-blue-900/30 dark:text-blue-400",
  active: "bg-emerald-100 text-emerald-700 border-emerald-200 dark:bg-emerald-900/30 dark:text-emerald-400",
  cancelled: "bg-destructive/10 text-destructive border-destructive/20",
  completed: "bg-muted text-muted-foreground border-border",
};

// ─── Schema ───────────────────────────────────────────────────────────────────
const tripSchema = z.object({
  routeId: z.string().min(1, "Select a route"),
  busId: z.string().min(1, "Select a bus"),
  departureDate: z.string().min(1, "Select departure date"),
  departureTime: z.string().min(1, "Select departure time"),
  arrivalDate: z.string().min(1, "Select arrival date"),
  arrivalTime: z.string().min(1, "Select arrival time"),
  priceAmount: z.coerce.number().min(0.01, "Price must be greater than 0"),
  currency: z.string().min(1, "Select currency"),
});
type TripFormData = z.infer<typeof tripSchema>;

// ─── Trip Form Dialog ─────────────────────────────────────────────────────────
function TripFormDialog({
  trip,
  routes,
  buses,
  onClose,
}: {
  trip?: { _id: Id<"trips">; routeId: Id<"routes">; busId: Id<"buses">; departureTime: string; arrivalTime: string; priceAmount: number; currency: string };
  routes: RouteOption[];
  buses: BusOption[];
  onClose: () => void;
}) {
  const { t } = useTranslation("owner");
  const createTrip = useMutation(api.trips.createTrip);
  const updateTrip = useMutation(api.trips.updateTrip);
  const [saving, setSaving] = useState(false);

  // Parse existing ISO strings for editing
  const existingDep = trip ? parseISO(trip.departureTime) : null;
  const existingArr = trip ? parseISO(trip.arrivalTime) : null;

  const { register, handleSubmit, setValue, watch, formState: { errors } } = useForm<TripFormData>({
    resolver: zodResolver(tripSchema),
    defaultValues: {
      routeId: trip?.routeId ?? "",
      busId: trip?.busId ?? "",
      departureDate: existingDep ? format(existingDep, "yyyy-MM-dd") : "",
      departureTime: existingDep ? format(existingDep, "HH:mm") : "",
      arrivalDate: existingArr ? format(existingArr, "yyyy-MM-dd") : "",
      arrivalTime: existingArr ? format(existingArr, "HH:mm") : "",
      priceAmount: trip?.priceAmount ?? 0,
      currency: trip?.currency ?? "USD",
    },
  });

  const routeId = watch("routeId");
  const busId = watch("busId");
  const currency = watch("currency");

  const onSubmit = async (data: TripFormData) => {
    const depISO = new Date(`${data.departureDate}T${data.departureTime}:00`).toISOString();
    const arrISO = new Date(`${data.arrivalDate}T${data.arrivalTime}:00`).toISOString();

    if (new Date(depISO) >= new Date(arrISO)) {
      toast.error(t("trips.time_error"));
      return;
    }

    setSaving(true);
    try {
      if (trip) {
        await updateTrip({
          tripId: trip._id,
          routeId: data.routeId as Id<"routes">,
          busId: data.busId as Id<"buses">,
          departureTime: depISO,
          arrivalTime: arrISO,
          priceAmount: data.priceAmount,
          currency: data.currency,
        });
        toast.success(t("trips.updated"));
      } else {
        await createTrip({
          routeId: data.routeId as Id<"routes">,
          busId: data.busId as Id<"buses">,
          departureTime: depISO,
          arrivalTime: arrISO,
          priceAmount: data.priceAmount,
          currency: data.currency,
        });
        toast.success(t("trips.scheduled"));
      }
      onClose();
    } catch {
      toast.error(t("trips.save_error"));
    } finally {
      setSaving(false);
    }
  };

  const routeLabel = (r: RouteOption) =>
    `${r.origin?.name ?? "?"}${r.originLoc ? ` (${r.originLoc.city})` : ""} → ${r.destination?.name ?? "?"}${r.destLoc ? ` (${r.destLoc.city})` : ""}`;

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{trip ? t("trips.edit_trip") : t("trips.schedule_new")}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          {/* Route */}
          <div className="space-y-1.5">
            <Label>{t("labels.route", { ns: "common" })}</Label>
            <Select value={routeId} onValueChange={(v) => setValue("routeId", v)}>
              <SelectTrigger><SelectValue placeholder={t("trips.select_route")} /></SelectTrigger>
              <SelectContent>
                {routes.map((r) => (
                  <SelectItem key={r._id} value={r._id}>{routeLabel(r)}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.routeId && <p className="text-xs text-destructive">{errors.routeId.message}</p>}
          </div>

          {/* Bus */}
          <div className="space-y-1.5">
            <Label>{t("labels.bus", { ns: "common" })}</Label>
            <Select value={busId} onValueChange={(v) => setValue("busId", v)}>
              <SelectTrigger><SelectValue placeholder={t("trips.select_bus")} /></SelectTrigger>
              <SelectContent>
                {buses.filter(b => b._id !== "").map((b) => (
                  <SelectItem key={b._id} value={b._id}>
                    {b.name} · {b.plateNumber} · {b.capacity} {t("labels.seats", { ns: "common" })}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.busId && <p className="text-xs text-destructive">{errors.busId.message}</p>}
          </div>

          {/* Departure */}
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

          {/* Arrival */}
          <div className="space-y-1.5">
            <Label>{t("labels.arrival", { ns: "common" })}</Label>
            <div className="grid grid-cols-2 gap-2">
              <Input type="date" {...register("arrivalDate")} />
              <Input type="time" {...register("arrivalTime")} />
            </div>
            {(errors.arrivalDate || errors.arrivalTime) && (
              <p className="text-xs text-destructive">{t("trips.arr_required")}</p>
            )}
          </div>

          {/* Price */}
          <div className="space-y-1.5">
            <Label>{t("labels.price_per_seat", { ns: "common" })}</Label>
            <div className="flex gap-2">
              <Select value={currency} onValueChange={(v) => setValue("currency", v)}>
                <SelectTrigger className="w-24 shrink-0"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {CURRENCIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                </SelectContent>
              </Select>
              <Input type="number" step="0.01" min={0} placeholder="0.00" {...register("priceAmount")} />
            </div>
            {errors.priceAmount && <p className="text-xs text-destructive">{errors.priceAmount.message}</p>}
          </div>

          <DialogFooter>
            <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>{t("buttons.cancel", { ns: "common" })}</Button>
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

// ─── Status Badge ─────────────────────────────────────────────────────────────
function StatusBadge({ status }: { status: string }) {
  return (
    <span className={cn("text-[10px] font-semibold px-2 py-0.5 rounded-full border capitalize", STATUS_STYLES[status] ?? STATUS_STYLES.scheduled)}>
      {status}
    </span>
  );
}

// ─── Status filter tabs ───────────────────────────────────────────────────────
const FILTER_TABS = ["all", "scheduled", "active", "completed", "cancelled"] as const;
type FilterTab = typeof FILTER_TABS[number];

// ─── Main Page ────────────────────────────────────────────────────────────────
export default function TripsManager() {
  const { t } = useTranslation("owner");
  const trips = useQuery(api.trips.listTrips, {});
  const routes = useQuery(api.trips.listRoutes, {});
  const buses = useQuery(api.fleet.listBuses, {});
  const updateTripStatus = useMutation(api.trips.updateTripStatus);
  const deleteTrip = useMutation(api.trips.deleteTrip);

  const [showForm, setShowForm] = useState(false);
  const [editTrip, setEditTrip] = useState<(typeof trips extends (infer T)[] | undefined ? T : never) | null>(null);
  const [deleteId, setDeleteId] = useState<Id<"trips"> | null>(null);
  const [filter, setFilter] = useState<FilterTab>("all");

  const filteredTrips = (trips ?? []).filter((t) => filter === "all" || t.status === filter);

  const activeRoutes = (routes ?? []).filter((r) => r.isActive) as RouteOption[];
  const activeBuses = ((buses ?? []).filter((b) => b.isActive)) as BusOption[];

  const handleStatusChange = async (tripId: Id<"trips">, status: string) => {
    try {
      await updateTripStatus({ tripId, status });
      toast.success(t("trips.status_changed", { status }));
    } catch {
      toast.error(t("trips.status_error"));
    }
  };

  const handleDelete = async () => {
    if (!deleteId) return;
    try {
      await deleteTrip({ tripId: deleteId });
      toast.success(t("trips.deleted"));
    } catch {
      toast.error(t("trips.delete_error"));
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
      cancelled: t("trips.filter.cancelled"),
    };
    return map[tab];
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("trips.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("trips.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setShowForm(true)} className="cursor-pointer">
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("trips.schedule")}
        </Button>
      </div>

      {/* Filter tabs */}
      <div className="flex gap-1.5 overflow-x-auto pb-1 scrollbar-thin">
        {FILTER_TABS.map((tab) => (
          <button
            key={tab}
            onClick={() => setFilter(tab)}
            className={cn(
              "px-3 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-colors cursor-pointer",
              filter === tab
                ? "bg-primary text-primary-foreground"
                : "bg-muted text-muted-foreground hover:bg-muted/80"
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

      {/* Trips list */}
      {trips === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-28 rounded-xl" />)}
        </div>
      ) : filteredTrips.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon"><CalendarIcon /></EmptyMedia>
            <EmptyTitle>{t("trips.no_trips", { filter: filter === "all" ? "" : filter })}</EmptyTitle>
            <EmptyDescription>
              {filter === "all"
                ? t("trips.no_trips_all")
                : t("trips.no_trips_filter", { filter })}
            </EmptyDescription>
          </EmptyHeader>
          {filter === "all" && (
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
            <Card key={trip._id} className={cn(
              "transition-all",
              trip.status === "cancelled" && "opacity-60",
              trip.status === "completed" && "opacity-70"
            )}>
              <CardContent className="p-4 space-y-3">
                {/* Route + status */}
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-1.5 font-semibold text-sm flex-wrap">
                    <span>{trip.origin?.name ?? "Unknown"}</span>
                    <ArrowRightIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                    <span>{trip.destination?.name ?? "Unknown"}</span>
                  </div>
                  <StatusBadge status={trip.status} />
                </div>

                {/* Details row */}
                <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
                  <span className="flex items-center gap-1">
                    <ClockIcon className="w-3 h-3" />
                    {format(parseISO(trip.departureTime), "dd MMM yyyy, HH:mm")}
                    <span className="text-foreground/40">→</span>
                    {format(parseISO(trip.arrivalTime), "HH:mm")}
                  </span>
                  <span className="flex items-center gap-1">
                    <BusIcon className="w-3 h-3" />
                    {trip.bus?.name ?? "Unknown"}
                  </span>
                  <span className="flex items-center gap-1">
                    <UsersIcon className="w-3 h-3" />
                    {trip.seatsAvailable}/{trip.totalSeats} {t("labels.seats", { ns: "common" })}
                  </span>
                  <span className="flex items-center gap-1 font-semibold text-foreground">
                    <TagIcon className="w-3 h-3" />
                    {trip.currency} {trip.priceAmount.toLocaleString()}
                  </span>
                </div>

                {/* Actions */}
                <div className="flex items-center gap-2 pt-1">
                  <Button
                    size="sm" variant="ghost"
                    className="h-7 text-xs cursor-pointer"
                    onClick={() => setEditTrip(trip)}
                    disabled={trip.status === "cancelled" || trip.status === "completed"}
                  >
                    <PencilIcon className="w-3 h-3 mr-1" /> {t("buttons.edit", { ns: "common" })}
                  </Button>

                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button size="sm" variant="ghost" className="h-7 text-xs cursor-pointer">
                        Status <ChevronDownIcon className="w-3 h-3 ml-1" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent>
                      {["scheduled", "active", "cancelled", "completed"].map((s) => (
                        <DropdownMenuItem
                          key={s}
                          className={cn("cursor-pointer capitalize", trip.status === s && "font-bold")}
                          onClick={() => handleStatusChange(trip._id, s)}
                        >
                          {s}
                        </DropdownMenuItem>
                      ))}
                    </DropdownMenuContent>
                  </DropdownMenu>

                  <Button
                    size="icon" variant="ghost"
                    className="h-7 w-7 ml-auto cursor-pointer text-destructive hover:text-destructive"
                    onClick={() => setDeleteId(trip._id)}
                  >
                    <TrashIcon className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Form dialog */}
      {(showForm || editTrip) && (
        <TripFormDialog
          trip={editTrip ?? undefined}
          routes={activeRoutes}
          buses={activeBuses}
          onClose={() => { setShowForm(false); setEditTrip(null); }}
        />
      )}

      {/* Delete confirm */}
      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("trips.delete_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>{t("trips.delete_desc")}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("buttons.cancel", { ns: "common" })}</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              {t("buttons.delete", { ns: "common" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
