import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import {
  RouteIcon, PlusIcon, TrashIcon, ArrowRightIcon, ClockIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Switch } from "@/components/ui/switch.tsx";
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
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from "@/components/ui/empty.tsx";
import { cn } from "@/lib/utils.ts";

type StationOption = { _id: Id<"stations">; name: string; location: { city: string; country: string } | null };

const routeSchema = z.object({
  originStationId: z.string().min(1, "Select origin"),
  destinationStationId: z.string().min(1, "Select destination"),
  estimatedDurationMinutes: z.coerce.number().min(1, "Duration required"),
});
type RouteFormData = z.infer<typeof routeSchema>;

function RouteDialog({ stations, onClose }: { stations: StationOption[]; onClose: () => void }) {
  const { t } = useTranslation("owner");
  const createRoute = useMutation(api.trips.createRoute);
  const [saving, setSaving] = useState(false);

  const { register, handleSubmit, setValue, watch, formState: { errors } } = useForm<RouteFormData>({
    resolver: zodResolver(routeSchema),
    defaultValues: { originStationId: "", destinationStationId: "", estimatedDurationMinutes: 60 },
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
      await createRoute({
        originStationId: data.originStationId as Id<"stations">,
        destinationStationId: data.destinationStationId as Id<"stations">,
        estimatedDurationMinutes: data.estimatedDurationMinutes,
      });
      toast.success(t("routes.created"));
      onClose();
    } catch {
      toast.error(t("routes.create_error"));
    } finally {
      setSaving(false);
    }
  };

  const stationLabel = (s: StationOption) => `${s.name}${s.location ? ` (${s.location.city})` : ""}`;

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-sm">
        <DialogHeader><DialogTitle>{t("routes.create_title")}</DialogTitle></DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          <div className="space-y-1.5">
            <Label>{t("routes.origin")}</Label>
            <Select value={originId} onValueChange={(v) => setValue("originStationId", v)}>
              <SelectTrigger><SelectValue placeholder={t("routes.select_origin")} /></SelectTrigger>
              <SelectContent>
                {stations.map((s) => (
                  <SelectItem key={s._id} value={s._id}>{stationLabel(s)}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.originStationId && <p className="text-xs text-destructive">{errors.originStationId.message}</p>}
          </div>
          <div className="space-y-1.5">
            <Label>{t("routes.destination")}</Label>
            <Select value={destId} onValueChange={(v) => setValue("destinationStationId", v)}>
              <SelectTrigger><SelectValue placeholder={t("routes.select_dest")} /></SelectTrigger>
              <SelectContent>
                {stations.filter(s => s._id !== originId).map((s) => (
                  <SelectItem key={s._id} value={s._id}>{stationLabel(s)}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.destinationStationId && <p className="text-xs text-destructive">{errors.destinationStationId.message}</p>}
          </div>
          <div className="space-y-1.5">
            <Label>{t("routes.duration")}</Label>
            <Input type="number" min={1} {...register("estimatedDurationMinutes")} />
            {errors.estimatedDurationMinutes && <p className="text-xs text-destructive">{errors.estimatedDurationMinutes.message}</p>}
          </div>
          <DialogFooter>
            <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>{t("buttons.cancel", { ns: "common" })}</Button>
            <Button type="submit" disabled={saving}>{saving ? t("routes.creating") : t("routes.create_btn")}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function formatDuration(mins: number) {
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return h > 0 ? `${h}h ${m > 0 ? `${m}m` : ""}`.trim() : `${m}m`;
}

export default function RoutesManager() {
  const { t } = useTranslation("owner");
  const routes = useQuery(api.trips.listRoutes, {});
  const stations = useQuery(api.fleet.listStations, {});
  const updateRoute = useMutation(api.trips.updateRoute);
  const deleteRoute = useMutation(api.trips.deleteRoute);

  const [showForm, setShowForm] = useState(false);
  const [deleteId, setDeleteId] = useState<Id<"routes"> | null>(null);

  const stationOptions: StationOption[] = (stations ?? []).map((s) => ({
    _id: s._id,
    name: s.name,
    location: s.location as { city: string; country: string } | null,
  }));

  const handleToggleActive = async (routeId: Id<"routes">, currentActive: boolean, durationMins: number) => {
    try {
      await updateRoute({ routeId, estimatedDurationMinutes: durationMins, isActive: !currentActive });
      toast.success(!currentActive ? t("routes.activated") : t("routes.deactivated"));
    } catch {
      toast.error(t("routes.update_error"));
    }
  };

  const handleDelete = async () => {
    if (!deleteId) return;
    try {
      await deleteRoute({ routeId: deleteId });
      toast.success(t("routes.deleted"));
    } catch {
      toast.error(t("routes.delete_error"));
    } finally {
      setDeleteId(null);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("routes.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("routes.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setShowForm(true)} className="cursor-pointer">
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("routes.add")}
        </Button>
      </div>

      {routes === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)}
        </div>
      ) : routes.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon"><RouteIcon /></EmptyMedia>
            <EmptyTitle>{t("routes.no_routes")}</EmptyTitle>
            <EmptyDescription>{t("routes.no_routes_desc")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" onClick={() => setShowForm(true)}>
              <PlusIcon className="w-4 h-4 mr-1.5" /> {t("routes.add_first")}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="space-y-3">
          {routes.map((route) => (
            <Card key={route._id} className={cn(!route.isActive && "opacity-60")}>
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0 mt-0.5">
                    <RouteIcon className="w-5 h-5 text-primary" />
                  </div>
                  <div className="flex-1 min-w-0">
                    {/* Route path */}
                    <div className="flex items-center gap-1.5 flex-wrap text-sm font-semibold">
                      <span className="truncate max-w-[120px]">
                        {route.origin?.name ?? "Unknown"}
                        {route.originLoc ? <span className="font-normal text-muted-foreground"> · {route.originLoc.city}</span> : ""}
                      </span>
                      <ArrowRightIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                      <span className="truncate max-w-[120px]">
                        {route.destination?.name ?? "Unknown"}
                        {route.destLoc ? <span className="font-normal text-muted-foreground"> · {route.destLoc.city}</span> : ""}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 mt-1.5 flex-wrap">
                      <span className="flex items-center gap-1 text-xs text-muted-foreground">
                        <ClockIcon className="w-3 h-3" />
                        {formatDuration(route.estimatedDurationMinutes)}
                      </span>
                      <Badge variant={route.isActive ? "default" : "secondary"} className="text-[10px] h-4 px-1.5">
                        {route.isActive ? t("status.active", { ns: "common" }) : t("status.inactive", { ns: "common" })}
                      </Badge>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <Switch
                      checked={route.isActive}
                      onCheckedChange={() => handleToggleActive(route._id, route.isActive, route.estimatedDurationMinutes)}
                      className="cursor-pointer"
                    />
                    <Button
                      size="icon" variant="ghost"
                      className="h-8 w-8 cursor-pointer text-destructive hover:text-destructive"
                      onClick={() => setDeleteId(route._id)}
                    >
                      <TrashIcon className="w-3.5 h-3.5" />
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {showForm && (
        <RouteDialog stations={stationOptions} onClose={() => setShowForm(false)} />
      )}

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("routes.delete_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>{t("routes.delete_desc")}</AlertDialogDescription>
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
