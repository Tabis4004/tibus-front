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
  BusIcon, PlusIcon, PencilIcon, TrashIcon, CheckCircleIcon, XCircleIcon,
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
import { cn } from "@/lib/utils.ts";

const AMENITIES = ["AC", "WiFi", "USB Charging", "Reclining Seats", "Toilet", "TV", "Snacks", "Luggage Storage"];

const busSchema = z.object({
  name: z.string().min(2, "Name required"),
  plateNumber: z.string().min(2, "Plate number required"),
  capacity: z.coerce.number().min(1, "Capacity must be at least 1").max(200),
  busType: z.string().min(1, "Select a bus type"),
});
type BusFormData = z.infer<typeof busSchema>;

type BusDoc = {
  _id: Id<"buses">;
  name: string;
  plateNumber: string;
  capacity: number;
  busType: string;
  amenities?: string[];
  isActive: boolean;
};

function BusFormDialog({
  bus,
  onClose,
}: {
  bus?: BusDoc;
  onClose: () => void;
}) {
  const { t } = useTranslation("owner");
  const createBus = useMutation(api.fleet.createBus);
  const updateBus = useMutation(api.fleet.updateBus);
  const [amenities, setAmenities] = useState<string[]>(bus?.amenities ?? []);
  const [isActive, setIsActive] = useState(bus?.isActive ?? true);
  const [saving, setSaving] = useState(false);

  const BUS_TYPES = [
    { value: "standard", label: t("fleet.type.standard") },
    { value: "luxury", label: t("fleet.type.luxury") },
    { value: "mini", label: t("fleet.type.mini") },
    { value: "vip", label: t("fleet.type.vip") },
  ];

  const { register, handleSubmit, setValue, watch, formState: { errors } } = useForm<BusFormData>({
    resolver: zodResolver(busSchema),
    defaultValues: {
      name: bus?.name ?? "",
      plateNumber: bus?.plateNumber ?? "",
      capacity: bus?.capacity ?? 40,
      busType: bus?.busType ?? "",
    },
  });

  const toggleAmenity = (a: string) =>
    setAmenities((prev) => prev.includes(a) ? prev.filter((x) => x !== a) : [...prev, a]);

  const onSubmit = async (data: BusFormData) => {
    setSaving(true);
    try {
      if (bus) {
        await updateBus({ busId: bus._id, ...data, amenities, isActive });
        toast.success(t("fleet.updated"));
      } else {
        await createBus({ ...data, amenities });
        toast.success(t("fleet.added"));
      }
      onClose();
    } catch {
      toast.error(t("fleet.save_error"));
    } finally {
      setSaving(false);
    }
  };

  const busType = watch("busType");

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{bus ? t("fleet.edit_bus") : t("fleet.add_new")}</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 py-1">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="name">{t("fleet.bus_name")}</Label>
              <Input id="name" placeholder="e.g. Express 01" {...register("name")} />
              {errors.name && <p className="text-xs text-destructive">{errors.name.message}</p>}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="plateNumber">{t("fleet.plate_number")}</Label>
              <Input id="plateNumber" placeholder="e.g. AB-1234" {...register("plateNumber")} />
              {errors.plateNumber && <p className="text-xs text-destructive">{errors.plateNumber.message}</p>}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="capacity">{t("fleet.capacity")}</Label>
              <Input id="capacity" type="number" min={1} max={200} {...register("capacity")} />
              {errors.capacity && <p className="text-xs text-destructive">{errors.capacity.message}</p>}
            </div>
            <div className="space-y-1.5">
              <Label>{t("fleet.bus_type")}</Label>
              <Select value={busType} onValueChange={(v) => setValue("busType", v)}>
                <SelectTrigger><SelectValue placeholder={t("fleet.select_type")} /></SelectTrigger>
                <SelectContent>
                  {BUS_TYPES.map((type) => (
                    <SelectItem key={type.value} value={type.value}>{type.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errors.busType && <p className="text-xs text-destructive">{errors.busType.message}</p>}
            </div>
          </div>

          {/* Amenities */}
          <div className="space-y-2">
            <Label>{t("labels.amenities", { ns: "common" })}</Label>
            <div className="flex flex-wrap gap-2">
              {AMENITIES.map((a) => (
                <button
                  key={a}
                  type="button"
                  onClick={() => toggleAmenity(a)}
                  className={cn(
                    "text-xs px-2.5 py-1 rounded-full border cursor-pointer transition-colors",
                    amenities.includes(a)
                      ? "bg-primary text-primary-foreground border-primary"
                      : "bg-muted text-muted-foreground border-border hover:border-primary/50"
                  )}
                >
                  {a}
                </button>
              ))}
            </div>
          </div>

          {bus && (
            <div className="flex items-center gap-3">
              <Switch id="isActive" checked={isActive} onCheckedChange={setIsActive} />
              <Label htmlFor="isActive">{t("fleet.bus_active")}</Label>
            </div>
          )}

          <DialogFooter>
            <Button type="button" variant="secondary" onClick={onClose} disabled={saving}>{t("buttons.cancel", { ns: "common" })}</Button>
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

export default function FleetManager() {
  const { t } = useTranslation("owner");
  const buses = useQuery(api.fleet.listBuses, {});
  const deleteBus = useMutation(api.fleet.deleteBus);
  const [showForm, setShowForm] = useState(false);
  const [editBus, setEditBus] = useState<BusDoc | null>(null);
  const [deleteId, setDeleteId] = useState<Id<"buses"> | null>(null);

  const BUS_TYPES = [
    { value: "standard", label: t("fleet.type.standard") },
    { value: "luxury", label: t("fleet.type.luxury") },
    { value: "mini", label: t("fleet.type.mini") },
    { value: "vip", label: t("fleet.type.vip") },
  ];

  const handleDelete = async () => {
    if (!deleteId) return;
    try {
      await deleteBus({ busId: deleteId });
      toast.success(t("fleet.removed"));
    } catch {
      toast.error(t("fleet.delete_error"));
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
        <Button size="sm" onClick={() => setShowForm(true)} className="cursor-pointer">
          <PlusIcon className="w-4 h-4 mr-1.5" /> {t("fleet.add")}
        </Button>
      </div>

      {buses === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)}
        </div>
      ) : buses.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon"><BusIcon /></EmptyMedia>
            <EmptyTitle>{t("fleet.no_buses")}</EmptyTitle>
            <EmptyDescription>{t("fleet.no_buses_desc")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" onClick={() => setShowForm(true)}>{t("fleet.add_first")}</Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="space-y-3">
          {buses.map((bus) => (
            <Card key={bus._id} className={cn(!bus.isActive && "opacity-60")}>
              <CardContent className="p-4 flex items-center gap-4">
                <div className="w-11 h-11 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                  <BusIcon className="w-5 h-5 text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-sm">{bus.name}</span>
                    <Badge variant="secondary" className="text-[10px] h-4 px-1.5">
                      {BUS_TYPES.find((type) => type.value === bus.busType)?.label ?? bus.busType}
                    </Badge>
                    {bus.isActive
                      ? <span className="flex items-center gap-0.5 text-[10px] text-emerald-600"><CheckCircleIcon className="w-3 h-3" />{t("status.active", { ns: "common" })}</span>
                      : <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground"><XCircleIcon className="w-3 h-3" />{t("status.inactive", { ns: "common" })}</span>
                    }
                  </div>
                  <div className="text-xs text-muted-foreground mt-0.5">
                    {bus.plateNumber} · {bus.capacity} {t("labels.seats", { ns: "common" })}
                    {bus.amenities && bus.amenities.length > 0 && ` · ${bus.amenities.slice(0, 2).join(", ")}${bus.amenities.length > 2 ? ` +${bus.amenities.length - 2}` : ""}`}
                  </div>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  <Button size="icon" variant="ghost" className="h-8 w-8 cursor-pointer" onClick={() => setEditBus(bus as BusDoc)}>
                    <PencilIcon className="w-3.5 h-3.5" />
                  </Button>
                  <Button size="icon" variant="ghost" className="h-8 w-8 cursor-pointer text-destructive hover:text-destructive" onClick={() => setDeleteId(bus._id)}>
                    <TrashIcon className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {(showForm || editBus) && (
        <BusFormDialog
          bus={editBus ?? undefined}
          onClose={() => { setShowForm(false); setEditBus(null); }}
        />
      )}

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("fleet.remove_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("fleet.remove_desc")}
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
