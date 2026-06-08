import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import {
  MapPinIcon,
  PlusIcon,
  PencilIcon,
  TrashIcon,
  BuildingIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
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
  Empty,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  EmptyDescription,
  EmptyContent,
} from "@/components/ui/empty.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import {
  listOwnerStationsSupabase,
  createOwnerStationSupabase,
  updateOwnerStationSupabase,
  deleteOwnerStationSupabase,
  type SupabaseOwnerStation,
} from "@/lib/supabase/owner-operations";

const stationSchema = z.object({
  name: z.string().min(2, "Station name required"),
  googleMapsLink: z.string().optional(),
});
type StationFormData = z.infer<typeof stationSchema>;

function StationDialog({
  station,
  appUserId,
  onClose,
  onSaved,
}: {
  station?: SupabaseOwnerStation;
  appUserId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t } = useTranslation("owner");
  const [saving, setSaving] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<StationFormData>({
    resolver: zodResolver(stationSchema),
    defaultValues: {
      name: station?.name ?? "",
      googleMapsLink: station?.address ?? "",
    },
  });

  const onSubmit = async (data: StationFormData) => {
    setSaving(true);
    try {
      if (station) {
        await updateOwnerStationSupabase({
          appUserId,
          stationId: station.id,
          name: data.name,
          googleMapsLink: data.googleMapsLink,
        });
        toast.success(t("stations.station_updated"));
      } else {
        await createOwnerStationSupabase({
          appUserId,
          name: data.name,
          googleMapsLink: data.googleMapsLink,
        });
        toast.success(t("stations.station_added"));
      }
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stations.station_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>
            {station ? t("stations.edit_station") : t("stations.add_station")}
          </DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          <div className="space-y-1.5">
            <Label>{t("stations.station_name")}</Label>
            <Input placeholder="Gare — Lomé" {...register("name")} />
            {errors.name && (
              <p className="text-xs text-destructive">{errors.name.message}</p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label>{t("stations.address")}</Label>
            <Input
              placeholder="https://maps.google.com/..."
              {...register("googleMapsLink")}
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>
              {t("buttons.cancel", { ns: "common" })}
            </Button>
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

export default function SupabaseStationsManager() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const [stations, setStations] = useState<SupabaseOwnerStation[] | undefined>(undefined);
  const [editStation, setEditStation] = useState<SupabaseOwnerStation | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<SupabaseOwnerStation | null>(null);

  const loadData = useCallback(async () => {
    if (!appUserId) return;
    setStations(undefined);
    try {
      setStations(await listOwnerStationsSupabase(appUserId));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stations.station_error"));
      setStations([]);
    }
  }, [appUserId, t]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  const cityNames = [
    ...new Set((stations ?? []).map((s) => s.location?.city).filter(Boolean)),
  ] as string[];

  const handleDelete = async () => {
    if (!deleteTarget || !appUserId) return;
    try {
      await deleteOwnerStationSupabase(appUserId, deleteTarget.id);
      toast.success(t("stations.station_removed"));
      void loadData();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stations.delete_error"));
    } finally {
      setDeleteTarget(null);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("stations.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("stations.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setShowForm(true)}>
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("stations.add_station")}
        </Button>
      </div>

      {stations === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 2 }).map((_, i) => (
            <Skeleton key={i} className="h-24 rounded-xl" />
          ))}
        </div>
      ) : stations.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <MapPinIcon />
            </EmptyMedia>
            <EmptyTitle>{t("stations.no_locations")}</EmptyTitle>
            <EmptyDescription>{t("stations.no_locations_desc")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" onClick={() => setShowForm(true)}>
              {t("stations.add_station")}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="space-y-3">
          {cityNames.map((cityName) => {
            const cityStations = (stations ?? []).filter(
              (s) => s.location?.city === cityName,
            );
            return (
              <Card key={cityName}>
                <CardContent className="p-4">
                  <div className="flex items-center gap-3 mb-3">
                    <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                      <MapPinIcon className="w-5 h-5 text-primary" />
                    </div>
                    <div className="flex-1">
                      <div className="font-semibold text-sm flex items-center gap-2">
                        {cityName}
                        <Badge variant="secondary" className="text-[10px] h-4 px-1.5">
                          {cityStations.length} {t("stations.station")}
                          {cityStations.length !== 1 ? "s" : ""}
                        </Badge>
                      </div>
                    </div>
                  </div>
                  <div className="space-y-2 pl-2 border-l-2 border-border ml-5">
                    {cityStations.map((station) => (
                      <div
                        key={station.id}
                        className="flex items-center gap-3 pl-3 py-1.5 rounded-lg hover:bg-muted/50"
                      >
                        <BuildingIcon className="w-4 h-4 text-muted-foreground shrink-0" />
                        <div className="flex-1 min-w-0">
                          <div className="text-sm font-medium">{station.name}</div>
                          {station.address && (
                            <a
                              href={station.address}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="text-xs text-primary truncate block"
                            >
                              {station.address}
                            </a>
                          )}
                        </div>
                        <div className="flex items-center gap-1 shrink-0">
                          <Button
                            size="icon"
                            variant="ghost"
                            className="h-7 w-7"
                            onClick={() => setEditStation(station)}
                          >
                            <PencilIcon className="w-3 h-3" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            className="h-7 w-7 text-destructive hover:text-destructive"
                            onClick={() => setDeleteTarget(station)}
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

      {(showForm || editStation) && appUserId && (
        <StationDialog
          station={editStation ?? undefined}
          appUserId={appUserId}
          onClose={() => {
            setShowForm(false);
            setEditStation(null);
          }}
          onSaved={() => void loadData()}
        />
      )}

      <AlertDialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("stations.remove_station")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("stations.remove_station_desc", { label: deleteTarget?.name })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("buttons.cancel", { ns: "common" })}</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {t("buttons.remove", { ns: "common" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
