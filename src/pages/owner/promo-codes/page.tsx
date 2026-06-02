import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { useTranslation } from "react-i18next";
import { format, parseISO } from "date-fns";
import { toast } from "sonner";
import { ConvexError } from "convex/values";
import {
  TagIcon,
  PlusIcon,
  TrashIcon,
  PercentIcon,
  CalendarIcon,
  HashIcon,
  ToggleLeftIcon,
  ToggleRightIcon,
  MapPinIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Separator } from "@/components/ui/separator.tsx";
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
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from "@/components/ui/empty.tsx";

function fmt(iso: string, pattern: string) {
  try { return format(parseISO(iso), pattern); } catch { return iso; }
}

export default function PromoCodesPage() {
  const { t } = useTranslation("owner");
  const codes = useQuery(api.promoCodes.listPromoCodes, {});
  const routes = useQuery(api.companies.getMyCompanyRoutes, {});
  const createPromo = useMutation(api.promoCodes.createPromoCode);
  const updatePromo = useMutation(api.promoCodes.updatePromoCode);
  const deletePromo = useMutation(api.promoCodes.deletePromoCode);

  const [showCreate, setShowCreate] = useState(false);
  const [newCode, setNewCode] = useState("");
  const [discountType, setDiscountType] = useState<"percentage" | "fixed">("percentage");
  const [discountValue, setDiscountValue] = useState("");
  const [validFrom, setValidFrom] = useState(new Date().toISOString().slice(0, 10));
  const [validUntil, setValidUntil] = useState("");
  const [maxUsage, setMaxUsage] = useState("");
  const [routeId, setRouteId] = useState<string>("all");
  const [creating, setCreating] = useState(false);

  const resetForm = () => {
    setNewCode("");
    setDiscountType("percentage");
    setDiscountValue("");
    setValidFrom(new Date().toISOString().slice(0, 10));
    setValidUntil("");
    setMaxUsage("");
    setRouteId("all");
  };

  const handleCreate = async () => {
    if (!newCode.trim() || !discountValue || !validUntil) {
      toast.error(t("promo.fill_required", { defaultValue: "Remplissez les champs requis" }));
      return;
    }
    setCreating(true);
    try {
      await createPromo({
        code: newCode.trim(),
        discountType,
        discountValue: parseFloat(discountValue),
        validFrom: new Date(validFrom).toISOString(),
        validUntil: new Date(validUntil + "T23:59:59").toISOString(),
        maxUsage: maxUsage ? parseInt(maxUsage) : undefined,
        routeId: routeId !== "all" ? (routeId as Id<"routes">) : undefined,
      });
      toast.success(t("promo.created", { defaultValue: "Code promo créé" }));
      resetForm();
      setShowCreate(false);
    } catch (err) {
      if (err instanceof ConvexError) {
        toast.error((err.data as { message: string }).message);
      } else {
        toast.error(t("promo.create_error", { defaultValue: "Erreur lors de la création" }));
      }
    } finally {
      setCreating(false);
    }
  };

  const handleToggle = async (promoId: Id<"promoCodes">, currentActive: boolean) => {
    try {
      await updatePromo({ promoId, isActive: !currentActive });
      toast.success(!currentActive
        ? t("promo.activated", { defaultValue: "Code activé" })
        : t("promo.deactivated", { defaultValue: "Code désactivé" })
      );
    } catch {
      toast.error(t("errors.generic", { ns: "common" }));
    }
  };

  const handleDelete = async (promoId: Id<"promoCodes">) => {
    try {
      await deletePromo({ promoId });
      toast.success(t("promo.deleted", { defaultValue: "Code supprimé" }));
    } catch {
      toast.error(t("errors.generic", { ns: "common" }));
    }
  };

  if (codes === undefined) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-40 w-full rounded-xl" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-extrabold tracking-tight">
            {t("promo.title", { defaultValue: "Codes Promo" })}
          </h1>
          <p className="text-sm text-muted-foreground">
            {t("promo.subtitle", { defaultValue: "Gérez vos codes promotionnels et réductions" })}
          </p>
        </div>
        <Button size="sm" className="cursor-pointer gap-1.5" onClick={() => setShowCreate(true)}>
          <PlusIcon className="w-4 h-4" />
          {t("promo.new", { defaultValue: "Nouveau" })}
        </Button>
      </div>

      {codes.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon"><TagIcon /></EmptyMedia>
            <EmptyTitle>{t("promo.empty_title", { defaultValue: "Aucun code promo" })}</EmptyTitle>
            <EmptyDescription>{t("promo.empty_desc", { defaultValue: "Créez votre premier code promo pour attirer plus de voyageurs" })}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" className="cursor-pointer" onClick={() => setShowCreate(true)}>
              {t("promo.create_first", { defaultValue: "Créer un code" })}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="grid gap-3">
          {codes.map((promo) => {
            const now = new Date().toISOString();
            const isExpired = now > promo.validUntil;
            const isExhausted = promo.maxUsage ? promo.usageCount >= promo.maxUsage : false;

            return (
              <Card key={promo._id}>
                <CardContent className="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex-1 min-w-0 space-y-2">
                      {/* Code + badges */}
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-mono font-bold text-lg tracking-wider text-primary">
                          {promo.code}
                        </span>
                        {promo.isActive && !isExpired && !isExhausted && (
                          <Badge variant="secondary" className="text-[10px] bg-green-500/10 text-green-600">
                            {t("promo.status_active", { defaultValue: "Actif" })}
                          </Badge>
                        )}
                        {isExpired && (
                          <Badge variant="secondary" className="text-[10px] bg-red-500/10 text-red-600">
                            {t("promo.status_expired", { defaultValue: "Expiré" })}
                          </Badge>
                        )}
                        {isExhausted && (
                          <Badge variant="secondary" className="text-[10px] bg-orange-500/10 text-orange-600">
                            {t("promo.status_exhausted", { defaultValue: "Épuisé" })}
                          </Badge>
                        )}
                        {!promo.isActive && (
                          <Badge variant="secondary" className="text-[10px]">
                            {t("promo.status_disabled", { defaultValue: "Désactivé" })}
                          </Badge>
                        )}
                      </div>

                      {/* Discount info */}
                      <div className="flex items-center gap-4 text-xs text-muted-foreground flex-wrap">
                        <span className="flex items-center gap-1">
                          <PercentIcon className="w-3 h-3" />
                          {promo.discountType === "percentage"
                            ? `${promo.discountValue}%`
                            : `${promo.currency ?? "XAF"} ${promo.discountValue.toLocaleString()}`
                          }
                        </span>
                        <span className="flex items-center gap-1">
                          <CalendarIcon className="w-3 h-3" />
                          {fmt(promo.validFrom, "dd/MM")} - {fmt(promo.validUntil, "dd/MM/yy")}
                        </span>
                        <span className="flex items-center gap-1">
                          <HashIcon className="w-3 h-3" />
                          {promo.usageCount}{promo.maxUsage ? `/${promo.maxUsage}` : ""} {t("promo.uses", { defaultValue: "utilisations" })}
                        </span>
                        {promo.routeLabel && (
                          <span className="flex items-center gap-1">
                            <MapPinIcon className="w-3 h-3" />
                            {promo.routeLabel}
                          </span>
                        )}
                      </div>
                    </div>

                    {/* Actions */}
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => handleToggle(promo._id, promo.isActive)}
                        className="p-1.5 rounded-md hover:bg-muted transition-colors cursor-pointer"
                        title={promo.isActive ? "Désactiver" : "Activer"}
                      >
                        {promo.isActive
                          ? <ToggleRightIcon className="w-5 h-5 text-green-600" />
                          : <ToggleLeftIcon className="w-5 h-5 text-muted-foreground" />
                        }
                      </button>
                      <button
                        onClick={() => handleDelete(promo._id)}
                        className="p-1.5 rounded-md hover:bg-destructive/10 transition-colors cursor-pointer"
                        title="Supprimer"
                      >
                        <TrashIcon className="w-4 h-4 text-destructive" />
                      </button>
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {/* Create dialog */}
      <Dialog open={showCreate} onOpenChange={setShowCreate}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("promo.create_title", { defaultValue: "Nouveau code promo" })}</DialogTitle>
          </DialogHeader>

          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>{t("promo.code_label", { defaultValue: "Code" })} *</Label>
              <Input
                placeholder="e.g. SUMMER2025"
                value={newCode}
                onChange={(e) => setNewCode(e.target.value.toUpperCase())}
                className="font-mono"
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>{t("promo.type_label", { defaultValue: "Type" })}</Label>
                <Select value={discountType} onValueChange={(v) => setDiscountType(v as "percentage" | "fixed")}>
                  <SelectTrigger className="cursor-pointer">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="percentage" className="cursor-pointer">% Pourcentage</SelectItem>
                    <SelectItem value="fixed" className="cursor-pointer">Montant fixe</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>{t("promo.value_label", { defaultValue: "Valeur" })} *</Label>
                <Input
                  type="number"
                  min="1"
                  placeholder={discountType === "percentage" ? "e.g. 10" : "e.g. 500"}
                  value={discountValue}
                  onChange={(e) => setDiscountValue(e.target.value)}
                />
              </div>
            </div>

            <Separator />

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>{t("promo.valid_from", { defaultValue: "Début" })} *</Label>
                <Input type="date" value={validFrom} onChange={(e) => setValidFrom(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>{t("promo.valid_until", { defaultValue: "Fin" })} *</Label>
                <Input type="date" value={validUntil} onChange={(e) => setValidUntil(e.target.value)} />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>{t("promo.max_usage", { defaultValue: "Limite d'usage" })}</Label>
                <Input
                  type="number"
                  min="1"
                  placeholder="Illimité"
                  value={maxUsage}
                  onChange={(e) => setMaxUsage(e.target.value)}
                />
              </div>
              <div className="space-y-1.5">
                <Label>{t("promo.route_label", { defaultValue: "Trajet" })}</Label>
                <Select value={routeId} onValueChange={setRouteId}>
                  <SelectTrigger className="cursor-pointer">
                    <SelectValue placeholder="Tous" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all" className="cursor-pointer">
                      {t("promo.all_routes", { defaultValue: "Tous les trajets" })}
                    </SelectItem>
                    {(routes ?? []).map((r) => (
                      <SelectItem key={r._id} value={r._id} className="cursor-pointer">
                        {r.originName} → {r.destName}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button variant="ghost" onClick={() => setShowCreate(false)} className="cursor-pointer">
              {t("buttons.cancel", { ns: "common" })}
            </Button>
            <Button onClick={handleCreate} disabled={creating} className="cursor-pointer">
              {creating ? t("processing", { ns: "common", defaultValue: "..." }) : t("promo.create_btn", { defaultValue: "Créer" })}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
