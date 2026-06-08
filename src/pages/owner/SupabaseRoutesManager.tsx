import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import { RouteIcon, PlusIcon, ArrowRightIcon, TagIcon } from "lucide-react";
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

function RouteDialog({
  stations,
  onClose,
  onSaved,
}: {
  stations: OwnerStationOption[];
  onClose: () => void;
  onSaved: () => void;
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

  const stationLabel = (s: OwnerStationOption) =>
    `${s.name}${s.city ? ` (${s.city})` : ""}`;

  const onSubmit = async (data: RouteFormData) => {
    if (data.originStationId === data.destinationStationId) {
      toast.error(t("routes.same_error"));
      return;
    }
    setSaving(true);
    try {
      await createOwnerRouteSupabase({
        originStationId: data.originStationId,
        destinationStationId: data.destinationStationId,
        price: data.price,
        kilometrage: data.kilometrage,
      });
      toast.success(t("routes.created"));
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("routes.create_error"));
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

export default function SupabaseRoutesManager() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const { companyId } = useOwnerCompany();
  const [routes, setRoutes] = useState<OwnerRouteOption[] | undefined>(undefined);
  const [stations, setStations] = useState<OwnerStationOption[]>([]);
  const [showForm, setShowForm] = useState(false);

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
      toast.error(err instanceof Error ? err.message : t("routes.create_error"));
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
                <div className="flex items-center gap-1.5 font-semibold text-sm flex-wrap">
                  <span>{route.originName}</span>
                  <ArrowRightIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                  <span>{route.destName}</span>
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
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {showForm && (
        <RouteDialog
          stations={stations}
          onClose={() => setShowForm(false)}
          onSaved={() => void loadData()}
        />
      )}
    </div>
  );
}
