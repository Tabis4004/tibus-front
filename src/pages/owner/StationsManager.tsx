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
  MapPinIcon, PlusIcon, PencilIcon, TrashIcon, BuildingIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Switch } from "@/components/ui/switch.tsx";
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

// ─── Types ────────────────────────────────────────────────────────────────────
type LocationInfo = { city: string; country: string } | null;
type StationDoc = {
  _id: Id<"stations">;
  cityId?: Id<"cities">;
  locationId?: Id<"locations">;
  name: string;
  address: string;
  latitude?: number;
  longitude?: number;
  isActive: boolean;
  location: LocationInfo;
};

type CityOption = { _id: string; name: string; countryName: string };

// ─── Station Form ─────────────────────────────────────────────────────────────
const stationSchema = z.object({
  name: z.string().min(2, "Station name required"),
  address: z.string().min(3, "Address required"),
  cityId: z.string().min(1, "Select a city"),
  latitude: z.string().optional(),
  longitude: z.string().optional(),
});
type StationFormData = z.infer<typeof stationSchema>;

function StationDialog({
  station,
  cities,
  defaultCityId,
  onClose,
}: {
  station?: StationDoc;
  cities: CityOption[];
  defaultCityId?: string;
  onClose: () => void;
}) {
  const { t } = useTranslation("owner");
  const createStation = useMutation(api.fleet.createStation);
  const updateStation = useMutation(api.fleet.updateStation);
  const [isActive, setIsActive] = useState(station?.isActive ?? true);
  const [saving, setSaving] = useState(false);

  const { register, handleSubmit, setValue, watch, formState: { errors } } = useForm<StationFormData>({
    resolver: zodResolver(stationSchema),
    defaultValues: {
      name: station?.name ?? "",
      address: station?.address ?? "",
      cityId: (station?.cityId ?? defaultCityId ?? "") as string,
      latitude: station?.latitude !== undefined ? String(station.latitude) : "",
      longitude: station?.longitude !== undefined ? String(station.longitude) : "",
    },
  });

  const cityId = watch("cityId");

  const onSubmit = async (data: StationFormData) => {
    setSaving(true);
    const lat = data.latitude ? parseFloat(data.latitude) : undefined;
    const lng = data.longitude ? parseFloat(data.longitude) : undefined;
    try {
      if (station) {
        await updateStation({
          stationId: station._id,
          name: data.name,
          address: data.address,
          isActive,
          latitude: isNaN(lat as number) ? undefined : lat,
          longitude: isNaN(lng as number) ? undefined : lng,
        });
        toast.success(t("stations.station_updated"));
      } else {
        await createStation({
          cityId: data.cityId as Id<"cities">,
          name: data.name,
          address: data.address,
          latitude: isNaN(lat as number) ? undefined : lat,
          longitude: isNaN(lng as number) ? undefined : lng,
        });
        toast.success(t("stations.station_added"));
      }
      onClose();
    } catch {
      toast.error(t("stations.station_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-sm">
        <DialogHeader><DialogTitle>{station ? t("stations.edit_station") : t("stations.add_station")}</DialogTitle></DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          {!station && (
            <div className="space-y-1.5">
              <Label>{t("stations.location_city")}</Label>
              <Select value={cityId} onValueChange={(v) => setValue("cityId", v)}>
                <SelectTrigger><SelectValue placeholder={t("stations.select_city")} /></SelectTrigger>
                <SelectContent>
                  {cities.map((c) => (
                    <SelectItem key={c._id} value={c._id}>{c.name}, {c.countryName}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errors.cityId && <p className="text-xs text-destructive">{errors.cityId.message}</p>}
            </div>
          )}
          <div className="space-y-1.5">
            <Label>{t("stations.station_name")}</Label>
            <Input placeholder="e.g. Central Bus Terminal" {...register("name")} />
            {errors.name && <p className="text-xs text-destructive">{errors.name.message}</p>}
          </div>
          <div className="space-y-1.5">
            <Label>{t("stations.address")}</Label>
            <Input placeholder="e.g. 12 Main Street, CBD" {...register("address")} />
            {errors.address && <p className="text-xs text-destructive">{errors.address.message}</p>}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>{t("stations.latitude", { defaultValue: "Latitude" })}</Label>
              <Input type="number" step="any" placeholder="e.g. 6.1725" {...register("latitude")} />
            </div>
            <div className="space-y-1.5">
              <Label>{t("stations.longitude", { defaultValue: "Longitude" })}</Label>
              <Input type="number" step="any" placeholder="e.g. 1.2314" {...register("longitude")} />
            </div>
          </div>
          {station && (
            <div className="flex items-center gap-3">
              <Switch id="isActive" checked={isActive} onCheckedChange={setIsActive} />
              <Label htmlFor="isActive">{t("stations.station_active")}</Label>
            </div>
          )}
          <DialogFooter>
            <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>{t("buttons.cancel", { ns: "common" })}</Button>
            <Button type="submit" disabled={saving}>
              {saving
                ? t("buttons.saving", { ns: "common" })
                : station
                ? t("company.save_btn")
                : t("stations.add_station")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────
export default function StationsManager() {
  const { t } = useTranslation("owner");
  const cities = useQuery(api.geography.listCities, {}) as CityOption[] | undefined;
  const stations = useQuery(api.fleet.listStations, {}) as StationDoc[] | undefined;
  const deleteStation = useMutation(api.fleet.deleteStation);

  const [stationDialog, setStationDialog] = useState<{ defaultCityId?: string; edit?: StationDoc } | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<{ type: "station"; id: Id<"stations">; label: string } | null>(null);

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      await deleteStation({ stationId: deleteTarget.id as Id<"stations"> });
      toast.success(t("stations.station_removed"));
    } catch {
      toast.error(t("stations.delete_error"));
    } finally {
      setDeleteTarget(null);
    }
  };

  // Group stations by city name
  const stationsByCity = (cityName: string) =>
    (stations ?? []).filter((s) => s.location?.city === cityName);

  // Get unique city names from stations
  const cityNames = [...new Set((stations ?? []).map((s) => s.location?.city).filter(Boolean))] as string[];

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("stations.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("stations.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setStationDialog({})} className="cursor-pointer">
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("stations.add_station")}
        </Button>
      </div>

      {stations === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 2 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)}
        </div>
      ) : stations.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon"><MapPinIcon /></EmptyMedia>
            <EmptyTitle>{t("stations.no_locations")}</EmptyTitle>
            <EmptyDescription>{t("stations.no_locations_desc")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" onClick={() => setStationDialog({})}>{t("stations.add_station")}</Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="space-y-3">
          {cityNames.map((cityName) => {
            const cityStations = stationsByCity(cityName);
            return (
              <Card key={cityName}>
                <CardContent className="p-4">
                  <div className="flex items-center gap-3 mb-3">
                    <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                      <MapPinIcon className="w-5 h-5 text-primary" />
                    </div>
                    <div className="flex-1 min-w-0 text-left">
                      <div className="font-semibold text-sm flex items-center gap-2">
                        {cityName}, {cityStations[0]?.location?.country ?? ""}
                        <Badge variant="secondary" className="text-[10px] h-4 px-1.5">
                          {cityStations.length} {t("stations.station")}{cityStations.length !== 1 ? "s" : ""}
                        </Badge>
                      </div>
                    </div>
                  </div>
                  <div className="space-y-2 pl-2 border-l-2 border-border ml-5">
                    {cityStations.map((s) => (
                      <div key={s._id} className="flex items-center gap-3 pl-3 py-1.5 rounded-lg hover:bg-muted/50 transition-colors">
                        <BuildingIcon className="w-4 h-4 text-muted-foreground shrink-0" />
                        <div className="flex-1 min-w-0">
                          <div className="text-sm font-medium flex items-center gap-2">
                            {s.name}
                            {!s.isActive && <span className="text-[10px] text-muted-foreground">({t("status.inactive", { ns: "common" })})</span>}
                          </div>
                          <div className="text-xs text-muted-foreground truncate">{s.address}</div>
                          {(s.latitude !== undefined && s.longitude !== undefined) && (
                            <div className="text-[10px] text-primary/70 mt-0.5">
                              {s.latitude.toFixed(4)}, {s.longitude.toFixed(4)}
                            </div>
                          )}
                        </div>
                        <div className="flex items-center gap-1 shrink-0">
                          <Button
                            size="icon" variant="ghost" className="h-7 w-7 cursor-pointer"
                            onClick={() => setStationDialog({ edit: s })}
                          >
                            <PencilIcon className="w-3 h-3" />
                          </Button>
                          <Button
                            size="icon" variant="ghost"
                            className="h-7 w-7 cursor-pointer text-destructive hover:text-destructive"
                            onClick={() => setDeleteTarget({ type: "station", id: s._id, label: s.name })}
                          >
                            <TrashIcon className="w-3 h-3" />
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {stationDialog && (
        <StationDialog
          station={stationDialog.edit}
          cities={cities ?? []}
          defaultCityId={stationDialog.defaultCityId}
          onClose={() => setStationDialog(null)}
        />
      )}

      <AlertDialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("stations.remove_station")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("stations.remove_station_desc", { label: deleteTarget?.label })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("buttons.cancel", { ns: "common" })}</AlertDialogCancel>
            <AlertDialogAction onClick={handleDelete} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              {t("buttons.remove", { ns: "common" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
