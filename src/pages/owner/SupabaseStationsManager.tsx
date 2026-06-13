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
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";
import { listCitiesSupabase } from "@/lib/supabase/geography.ts";
import {
  listOwnerStationsSupabase,
  listOwnerTeamSupabase,
  createOwnerStationSupabase,
  updateOwnerStationSupabase,
  deleteOwnerStationSupabase,
  type SupabaseOwnerStation,
  type SupabaseOwnerTeamMember,
} from "@/lib/supabase/owner-operations";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";

const stationSchema = z.object({
  name: z.string().min(2, "Station name required"),
  cityId: z.string().min(1, "City required"),
  googleMapsLink: z.string().optional(),
  gestionnaireUserId: z.string().optional(),
  gestionnaireSharePct: z.coerce.number().min(0).max(100),
  gestionnaireSharePctReservation: z.coerce.number().min(0).max(100),
});
type StationFormData = z.infer<typeof stationSchema>;

function StationDialog({
  station,
  appUserId,
  companyId,
  countryId,
  onClose,
  onSaved,
}: {
  station?: SupabaseOwnerStation;
  appUserId: string;
  companyId: string;
  countryId: string | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t } = useTranslation("owner");
  const [saving, setSaving] = useState(false);
  const [team, setTeam] = useState<SupabaseOwnerTeamMember[]>([]);
  const [cities, setCities] = useState<{ id: string; name: string }[]>([]);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<StationFormData>({
    resolver: zodResolver(stationSchema),
    defaultValues: {
      name: station?.name ?? "",
      cityId: station?.cityId ?? "",
      googleMapsLink: station?.address ?? "",
      gestionnaireUserId: station?.gestionnaireUserId ?? "",
      gestionnaireSharePct: station?.gestionnaireSharePct ?? 0,
      gestionnaireSharePctReservation: station?.gestionnaireSharePctReservation ?? station?.gestionnaireSharePct ?? 0,
    },
  });

  useEffect(() => {
    if (!countryId) {
      setCities([]);
      return;
    }
    void listCitiesSupabase(countryId)
      .then((rows) => setCities(rows.map((row) => ({ id: row._id, name: row.name }))))
      .catch(() => setCities([]));
  }, [countryId]);

  useEffect(() => {
    if (!station) return;
    void listOwnerTeamSupabase(appUserId, companyId).then(setTeam).catch(() => setTeam([]));
  }, [appUserId, companyId, station]);

  const selectedManagerId = watch("gestionnaireUserId");
  const selectedCityId = watch("cityId");

  const onSubmit = async (data: StationFormData) => {
    setSaving(true);
    try {
      if (station) {
        await updateOwnerStationSupabase({
          appUserId,
          companyId,
          stationId: station.id,
          name: data.name,
          cityId: data.cityId,
          googleMapsLink: data.googleMapsLink,
          gestionnaireUserId: data.gestionnaireUserId || null,
          gestionnaireSharePct: data.gestionnaireSharePct,
          gestionnaireSharePctReservation: data.gestionnaireSharePctReservation,
        });
        toast.success(t("stations.station_updated"));
      } else {
        await createOwnerStationSupabase({
          appUserId,
          companyId,
          name: data.name,
          cityId: data.cityId,
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
            <Input placeholder="Gare Adjamé" {...register("name")} />
            {errors.name && (
              <p className="text-xs text-destructive">{errors.name.message}</p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label>{t("stations.city")}</Label>
            <Select
              value={selectedCityId}
              onValueChange={(value) => setValue("cityId", value, { shouldValidate: true })}
            >
              <SelectTrigger>
                <SelectValue placeholder={t("stations.city_placeholder")} />
              </SelectTrigger>
              <SelectContent>
                {cities.map((city) => (
                  <SelectItem key={city.id} value={city.id}>
                    {city.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.cityId && (
              <p className="text-xs text-destructive">{t("stations.city_required")}</p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label>{t("stations.address")}</Label>
            <Input
              placeholder="https://maps.google.com/..."
              {...register("googleMapsLink")}
            />
          </div>
          {station && (
            <>
              <div className="space-y-1.5">
                <Label>{t("stations.manager")}</Label>
                <Select
                  value={selectedManagerId || "__none__"}
                  onValueChange={(value) =>
                    setValue("gestionnaireUserId", value === "__none__" ? "" : value)
                  }
                >
                  <SelectTrigger>
                    <SelectValue placeholder={t("stations.manager_placeholder")} />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">{t("stations.no_manager")}</SelectItem>
                    {team.map((member) => (
                      <SelectItem key={member.id} value={member.id}>
                        {member.name}
                        {member.email ? ` (${member.email})` : ""}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>{t("stations.share_pct_counter")}</Label>
                <Input
                  type="number"
                  min={0}
                  max={100}
                  step={0.5}
                  {...register("gestionnaireSharePct")}
                />
                <p className="text-xs text-muted-foreground">{t("stations.share_pct_counter_hint")}</p>
              </div>
              <div className="space-y-1.5">
                <Label>{t("stations.share_pct_reservation")}</Label>
                <Input
                  type="number"
                  min={0}
                  max={100}
                  step={0.5}
                  {...register("gestionnaireSharePctReservation")}
                />
                <p className="text-xs text-muted-foreground">{t("stations.share_pct_reservation_hint")}</p>
              </div>
            </>
          )}
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
  const { companyId, selectedCompany } = useOwnerCompany();
  const [stations, setStations] = useState<SupabaseOwnerStation[] | undefined>(undefined);
  const [editStation, setEditStation] = useState<SupabaseOwnerStation | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<SupabaseOwnerStation | null>(null);

  const loadData = useCallback(async () => {
    if (!appUserId || !companyId) return;
    setStations(undefined);
    try {
      setStations(await listOwnerStationsSupabase(appUserId, companyId));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stations.station_error"));
      setStations([]);
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

  const cityNames = [
    ...new Set((stations ?? []).map((s) => s.cityName).filter(Boolean)),
  ] as string[];

  const handleDelete = async () => {
    if (!deleteTarget || !appUserId) return;
    try {
      await deleteOwnerStationSupabase(appUserId, deleteTarget.id, companyId);
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
            const cityStations = (stations ?? []).filter((s) => s.cityName === cityName);
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
                          {(station.gestionnaireSharePct > 0 || station.gestionnaireSharePctReservation > 0) && (
                            <p className="text-[11px] text-muted-foreground">
                              {station.gestionnaireName ?? t("stations.no_manager")} ·{" "}
                              {t("stations.share_pct_counter_short")} {station.gestionnaireSharePct}% ·{" "}
                              {t("stations.share_pct_reservation_short")} {station.gestionnaireSharePctReservation}%
                            </p>
                          )}
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

      {(showForm || editStation) && appUserId && companyId && (
        <StationDialog
          station={editStation ?? undefined}
          appUserId={appUserId}
          companyId={companyId}
          countryId={selectedCompany?.countryId ?? null}
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
