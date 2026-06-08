import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import {
  BusIcon,
  PlusIcon,
  PencilIcon,
  TrashIcon,
  CheckCircleIcon,
  XCircleIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
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
  listOwnerFleetBusesSupabase,
  createOwnerBusSupabase,
  updateOwnerBusSupabase,
  deleteOwnerBusSupabase,
  type SupabaseOwnerBus,
} from "@/lib/supabase/owner-operations";

const busSchema = z.object({
  name: z.string().min(2, "Name required"),
  plateNumber: z.string().min(2, "Plate number required"),
  capacity: z.coerce.number().min(1).max(200),
});
type BusFormData = z.infer<typeof busSchema>;

function BusFormDialog({
  bus,
  appUserId,
  companyId,
  onClose,
  onSaved,
}: {
  bus?: SupabaseOwnerBus;
  appUserId: string;
  companyId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t } = useTranslation("owner");
  const [isActive, setIsActive] = useState(bus?.isActive ?? true);
  const [saving, setSaving] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<BusFormData>({
    resolver: zodResolver(busSchema),
    defaultValues: {
      name: bus?.name ?? "",
      plateNumber: bus?.plateNumber ?? "",
      capacity: bus?.capacity ?? 40,
    },
  });

  const onSubmit = async (data: BusFormData) => {
    setSaving(true);
    try {
      if (bus) {
        await updateOwnerBusSupabase({
          appUserId,
          companyId,
          busId: bus.id,
          ...data,
          isActive,
        });
        toast.success(t("fleet.updated"));
      } else {
        await createOwnerBusSupabase({ appUserId, companyId, ...data });
        toast.success(t("fleet.added"));
      }
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("fleet.save_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{bus ? t("fleet.edit_bus") : t("fleet.add_new")}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>{t("fleet.bus_name")}</Label>
              <Input placeholder="Express 01" {...register("name")} />
              {errors.name && (
                <p className="text-xs text-destructive">{errors.name.message}</p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label>{t("fleet.plate_number")}</Label>
              <Input placeholder="TG-1234-AB" {...register("plateNumber")} />
              {errors.plateNumber && (
                <p className="text-xs text-destructive">{errors.plateNumber.message}</p>
              )}
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>{t("fleet.capacity")}</Label>
            <Input type="number" min={1} max={200} {...register("capacity")} />
            {errors.capacity && (
              <p className="text-xs text-destructive">{errors.capacity.message}</p>
            )}
          </div>
          {bus && (
            <div className="flex items-center gap-3">
              <Switch checked={isActive} onCheckedChange={setIsActive} />
              <Label>{t("fleet.bus_active")}</Label>
            </div>
          )}
          <DialogFooter>
            <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>
              {t("buttons.cancel", { ns: "common" })}
            </Button>
            <Button type="submit" disabled={saving}>
              {saving
                ? t("buttons.saving", { ns: "common" })
                : bus
                  ? t("company.save_btn")
                  : t("fleet.add")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export default function SupabaseFleetManager() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const { companyId } = useOwnerCompany();
  const [buses, setBuses] = useState<SupabaseOwnerBus[] | undefined>(undefined);
  const [showForm, setShowForm] = useState(false);
  const [editBus, setEditBus] = useState<SupabaseOwnerBus | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    if (!appUserId || !companyId) return;
    setBuses(undefined);
    try {
      setBuses(await listOwnerFleetBusesSupabase(appUserId, companyId));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("fleet.save_error"));
      setBuses([]);
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

  const handleDelete = async () => {
    if (!deleteId || !appUserId) return;
    try {
      await deleteOwnerBusSupabase(appUserId, deleteId, companyId);
      toast.success(t("fleet.removed"));
      void loadData();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("fleet.delete_error"));
    } finally {
      setDeleteId(null);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("fleet.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("fleet.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setShowForm(true)}>
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("fleet.add")}
        </Button>
      </div>

      {buses === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-20 rounded-xl" />
          ))}
        </div>
      ) : buses.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <BusIcon />
            </EmptyMedia>
            <EmptyTitle>{t("fleet.no_buses")}</EmptyTitle>
            <EmptyDescription>{t("fleet.no_buses_desc")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" onClick={() => setShowForm(true)}>
              {t("fleet.add_first")}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="space-y-3">
          {buses.map((bus) => (
            <Card key={bus.id} className={cn(!bus.isActive && "opacity-60")}>
              <CardContent className="p-4 flex items-center gap-4">
                <div className="w-11 h-11 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                  <BusIcon className="w-5 h-5 text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-sm">{bus.name}</span>
                    {bus.isActive ? (
                      <span className="flex items-center gap-0.5 text-[10px] text-emerald-600">
                        <CheckCircleIcon className="w-3 h-3" />
                        {t("status.active", { ns: "common" })}
                      </span>
                    ) : (
                      <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground">
                        <XCircleIcon className="w-3 h-3" />
                        {t("status.inactive", { ns: "common" })}
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-muted-foreground mt-0.5">
                    {bus.plateNumber} · {bus.capacity}{" "}
                    {t("labels.seats", { ns: "common" })}
                  </div>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-8 w-8"
                    onClick={() => setEditBus(bus)}
                  >
                    <PencilIcon className="w-3.5 h-3.5" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-8 w-8 text-destructive hover:text-destructive"
                    onClick={() => setDeleteId(bus.id)}
                  >
                    <TrashIcon className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {(showForm || editBus) && appUserId && companyId && (
        <BusFormDialog
          bus={editBus ?? undefined}
          appUserId={appUserId}
          companyId={companyId}
          onClose={() => {
            setShowForm(false);
            setEditBus(null);
          }}
          onSaved={() => void loadData()}
        />
      )}

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("fleet.remove_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>{t("fleet.remove_desc")}</AlertDialogDescription>
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
