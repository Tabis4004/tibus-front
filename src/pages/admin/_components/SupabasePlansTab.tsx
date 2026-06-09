import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { PlusIcon, RefreshCwIcon, SettingsIcon, TrashIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog.tsx";
import { cn } from "@/lib/utils.ts";
import {
  createAdminSubscriptionPlanSupabase,
  deleteAdminPlanDurationSupabase,
  deleteAdminSubscriptionPlanSupabase,
  listAdminSubscriptionPlansSupabase,
  updateAdminSubscriptionPlanSupabase,
  upsertAdminPlanDurationSupabase,
  type AdminSubscriptionPlan,
} from "@/lib/supabase/admin-subscriptions.ts";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";

type CountryOption = { id: string; name: string; currency: string | null };

export default function SupabasePlansTab({
  countries,
  onDataChanged,
}: {
  countries: CountryOption[];
  onDataChanged?: () => void;
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [plans, setPlans] = useState<AdminSubscriptionPlan[] | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState("");
  const [countryId, setCountryId] = useState(countries[0]?.id ?? "");
  const [durationDays, setDurationDays] = useState("30");
  const [price, setPrice] = useState("0");
  const [isDefault, setIsDefault] = useState(false);
  const [saving, setSaving] = useState(false);

  const [durationPlan, setDurationPlan] = useState<AdminSubscriptionPlan | null>(null);
  const [durationPrice, setDurationPrice] = useState("0");
  const [durationDaysAdd, setDurationDaysAdd] = useState("30");
  const [durationSaving, setDurationSaving] = useState(false);

  const load = useCallback(async (silent = false) => {
    if (!silent) setPlans(undefined);
    else setRefreshing(true);
    setError(null);
    try {
      setPlans(await listAdminSubscriptionPlansSupabase());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur chargement");
      setPlans([]);
    } finally {
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (!countryId && countries[0]?.id) setCountryId(countries[0].id);
  }, [countries, countryId]);

  const notifyChanged = () => onDataChanged?.();

  const handleCreate = async () => {
    if (!name.trim() || !countryId) return;
    setSaving(true);
    try {
      await createAdminSubscriptionPlanSupabase({
        name: name.trim(),
        countryId,
        isDefault,
        price: Number(price) || 0,
        durationDays: Number(durationDays) || 30,
      });
      toast.success(t("plans.created"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.plans",
        action: "create",
        summary: `Plan créé : ${name.trim()} (${durationDays} j, ${price})`,
        metadata: { countryId, isDefault },
      });
      setShowAdd(false);
      setName("");
      setDurationDays("30");
      setPrice("0");
      setIsDefault(false);
      await load(true);
      notifyChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("plans.create_error"));
    } finally {
      setSaving(false);
    }
  };

  const handleSetDefault = async (plan: AdminSubscriptionPlan) => {
    try {
      await updateAdminSubscriptionPlanSupabase({ planId: plan.id, isDefault: true });
      toast.success(t("plans.set_default"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.plans",
        action: "update",
        summary: `Plan par défaut : ${plan.name}`,
        metadata: { planId: plan.id },
      });
      await load(true);
      notifyChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("plans.update_error"));
    }
  };

  const handleDeletePlan = async (planId: string) => {
    if (!window.confirm(t("plans.delete_confirm", { defaultValue: "Supprimer ce plan ?" }))) return;
    try {
      await deleteAdminSubscriptionPlanSupabase(planId);
      toast.success(t("plans.deleted"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.plans",
        action: "delete",
        summary: `Plan supprimé (${planId})`,
        metadata: { planId },
      });
      await load(true);
      notifyChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("plans.delete_error"));
    }
  };

  const handleAddDuration = async () => {
    if (!durationPlan) return;
    setDurationSaving(true);
    try {
      await upsertAdminPlanDurationSupabase({
        planId: durationPlan.id,
        price: Number(durationPrice) || 0,
        durationDays: Number(durationDaysAdd) || 30,
      });
      toast.success(t("plans.updated"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.plans",
        action: "create",
        summary: `Durée plan ${durationPlan.name} : ${durationDaysAdd} j / ${durationPrice}`,
        metadata: { planId: durationPlan.id },
      });
      setDurationPlan(null);
      await load(true);
      notifyChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("plans.update_error"));
    } finally {
      setDurationSaving(false);
    }
  };

  const handleDeleteDuration = async (durationId: string) => {
    try {
      await deleteAdminPlanDurationSupabase(durationId);
      void recordPlatformAuditSupabase({
        moduleKey: "admin.plans",
        action: "delete",
        summary: `Durée de plan supprimée (${durationId})`,
        metadata: { durationId },
      });
      await load(true);
      notifyChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("plans.update_error"));
    }
  };

  const selectedCountry = countries.find((c) => c.id === countryId);

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between gap-3">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              <SettingsIcon className="w-4 h-4" />
              {t("plans.title")}
            </CardTitle>
            <p className="text-xs text-muted-foreground mt-1">{t("plans.desc")}</p>
          </div>
          <div className="flex items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => void load(true)}
              disabled={refreshing || plans === undefined}
              className="cursor-pointer"
            >
              <RefreshCwIcon className={cn("w-4 h-4", refreshing && "animate-spin")} />
            </Button>
            <Button size="sm" onClick={() => setShowAdd(true)} className="cursor-pointer">
              <PlusIcon className="w-4 h-4 mr-1" /> {t("plans.add")}
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {plans === undefined ? (
          <div className="space-y-2">
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : error ? (
          <p className="text-sm text-destructive">{error}</p>
        ) : plans.length === 0 ? (
          <div className="rounded-xl border border-dashed p-8 text-center space-y-3">
            <p className="font-medium">{t("plans.no_plans")}</p>
            <p className="text-sm text-muted-foreground">
              {t("plans.no_plans_desc", { defaultValue: "Créez des plans d'abonnement par pays." })}
            </p>
            <Button size="sm" onClick={() => setShowAdd(true)} className="cursor-pointer">
              <PlusIcon className="w-4 h-4 mr-1" /> {t("plans.add")}
            </Button>
          </div>
        ) : (
          plans.map((plan) => (
            <div key={plan.id} className="rounded-xl border p-4 space-y-3">
              <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                <div className="space-y-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-semibold">{plan.name}</span>
                    {plan.isDefault && (
                      <Badge className="text-[9px] bg-blue-500/10 text-blue-600 border-blue-500/30">
                        {t("plans.default_trial")}
                      </Badge>
                    )}
                    <Badge variant="secondary">{plan.countryName ?? plan.currency ?? "—"}</Badge>
                  </div>
                  <div className="flex flex-wrap gap-1">
                    {plan.durations.length === 0 ? (
                      <span className="text-xs text-muted-foreground">{t("plan_none")}</span>
                    ) : (
                      plan.durations.map((duration) => (
                        <Badge key={duration.id} variant="outline" className="gap-1 pr-1">
                          {duration.price === 0
                            ? t("plans.free")
                            : `${duration.price.toLocaleString()} ${plan.currency ?? ""}`}
                          {" / "}
                          {duration.duration} {t("plans.days")}
                          <button
                            type="button"
                            className="ml-1 rounded hover:bg-destructive/10 p-0.5"
                            onClick={() => void handleDeleteDuration(duration.id)}
                            aria-label={tc("buttons.delete")}
                          >
                            <TrashIcon className="w-3 h-3 text-destructive" />
                          </button>
                        </Badge>
                      ))
                    )}
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-1">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-xs cursor-pointer"
                    onClick={() => {
                      setDurationPlan(plan);
                      setDurationPrice("0");
                      setDurationDaysAdd("30");
                    }}
                  >
                    <PlusIcon className="w-3 h-3 mr-1" />
                    {t("plans.add_duration", { defaultValue: "Durée" })}
                  </Button>
                  {!plan.isDefault && (
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-xs cursor-pointer"
                      onClick={() => void handleSetDefault(plan)}
                    >
                      {t("plans.make_default")}
                    </Button>
                  )}
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-xs text-destructive cursor-pointer"
                    onClick={() => void handleDeletePlan(plan.id)}
                  >
                    <TrashIcon className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </div>
            </div>
          ))
        )}
      </CardContent>

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("plans.add_title")}</DialogTitle>
            <DialogDescription>{t("plans.add_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>{t("plans.name_label")} *</Label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Mensuel, Trimestriel…"
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("geo.select_country")} *</Label>
              <Select value={countryId} onValueChange={setCountryId}>
                <SelectTrigger>
                  <SelectValue placeholder={t("geo.select_country")} />
                </SelectTrigger>
                <SelectContent>
                  {countries.map((country) => (
                    <SelectItem key={country.id} value={country.id}>
                      {country.name}
                      {country.currency ? ` (${country.currency})` : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>{t("plans.duration_label")} *</Label>
                <Input
                  type="number"
                  value={durationDays}
                  onChange={(e) => setDurationDays(e.target.value)}
                  min={1}
                />
              </div>
              <div className="space-y-1.5">
                <Label>{t("plans.price_label")} *</Label>
                <Input
                  type="number"
                  value={price}
                  onChange={(e) => setPrice(e.target.value)}
                  min={0}
                />
              </div>
            </div>
            {selectedCountry?.currency && (
              <p className="text-xs text-muted-foreground">
                {t("plans.currency_label")}: {selectedCountry.currency}
              </p>
            )}
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isDefault}
                onChange={(e) => setIsDefault(e.target.checked)}
                className="rounded border-border"
              />
              <span className="text-sm">{t("plans.set_as_default")}</span>
            </label>
            <p className="text-[11px] text-muted-foreground">{t("plans.default_hint")}</p>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAdd(false)} className="cursor-pointer">
              {tc("buttons.cancel")}
            </Button>
            <Button
              onClick={() => void handleCreate()}
              disabled={saving || !name.trim() || !countryId}
              className="cursor-pointer"
            >
              {saving ? tc("buttons.saving") : t("plans.add")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={durationPlan !== null} onOpenChange={(open) => !open && setDurationPlan(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>{t("plans.add_duration_title", { defaultValue: "Ajouter une durée" })}</DialogTitle>
            <DialogDescription>
              {durationPlan?.name} — {durationPlan?.countryName}
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-3 py-2">
            <div className="space-y-1.5">
              <Label>{t("plans.duration_label")}</Label>
              <Input
                type="number"
                value={durationDaysAdd}
                onChange={(e) => setDurationDaysAdd(e.target.value)}
                min={1}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("plans.price_label")}</Label>
              <Input
                type="number"
                value={durationPrice}
                onChange={(e) => setDurationPrice(e.target.value)}
                min={0}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setDurationPlan(null)} className="cursor-pointer">
              {tc("buttons.cancel")}
            </Button>
            <Button
              onClick={() => void handleAddDuration()}
              disabled={durationSaving}
              className="cursor-pointer"
            >
              {durationSaving ? tc("buttons.saving") : tc("buttons.save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
