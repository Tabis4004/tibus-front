import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { PercentIcon, PlusIcon, TrashIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  deleteCounterCommissionTierSupabase,
  listCounterCommissionTiersSupabase,
  upsertCounterCommissionTierSupabase,
  type CounterCommissionTier,
} from "@/lib/supabase/counter-seller-commission.ts";

type DraftTier = {
  roleScope: "vendeur" | "vendeur_gare";
  minAmount: string;
  maxAmount: string;
  commissionType: "fixed" | "percentage";
  commissionValue: string;
};

const emptyDraft = (): DraftTier => ({
  roleScope: "vendeur_gare",
  minAmount: "0",
  maxAmount: "",
  commissionType: "percentage",
  commissionValue: "5",
});

function formatTierLabel(tier: CounterCommissionTier, t: (key: string) => string) {
  const scope =
    tier.roleScope === "vendeur_gare" ? t("gare.commission_scope_gare") : t("gare.commission_scope_company");
  const range =
    tier.maxAmount != null
      ? `${tier.minAmount.toLocaleString()} – ${tier.maxAmount.toLocaleString()}`
      : `${tier.minAmount.toLocaleString()}+`;
  const value =
    tier.commissionType === "fixed"
      ? `${tier.commissionValue.toLocaleString()}`
      : `${tier.commissionValue}%`;
  return `${scope} · ${range} · ${value}`;
}

export default function CounterCommissionTiersPanel({
  companyId,
  gareId,
}: {
  companyId: string;
  gareId?: string | null;
}) {
  const { t } = useTranslation("owner");
  const [tiers, setTiers] = useState<CounterCommissionTier[] | undefined>(undefined);
  const [draft, setDraft] = useState<DraftTier>(emptyDraft);
  const [saving, setSaving] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);

  const loadTiers = useCallback(async () => {
    setTiers(undefined);
    try {
      setTiers(await listCounterCommissionTiersSupabase(companyId, gareId ?? null));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare.commission_load_error"));
      setTiers([]);
    }
  }, [companyId, gareId, t]);

  useEffect(() => {
    void loadTiers();
  }, [loadTiers]);

  const handleCreate = async () => {
    setSaving(true);
    try {
      await upsertCounterCommissionTierSupabase({
        companyId,
        gareId: gareId ?? null,
        roleScope: draft.roleScope,
        minAmount: Number(draft.minAmount) || 0,
        maxAmount: draft.maxAmount.trim() ? Number(draft.maxAmount) : null,
        commissionType: draft.commissionType,
        commissionValue: Number(draft.commissionValue) || 0,
      });
      toast.success(t("gare.commission_saved"));
      setDraft(emptyDraft());
      void loadTiers();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare.commission_save_error"));
    } finally {
      setSaving(false);
    }
  };

  const handleToggle = async (tier: CounterCommissionTier, active: boolean) => {
    setBusyId(tier.id);
    try {
      await upsertCounterCommissionTierSupabase({
        id: tier.id,
        companyId: tier.companyId,
        gareId: tier.gareId,
        roleScope: tier.roleScope,
        minAmount: tier.minAmount,
        maxAmount: tier.maxAmount,
        commissionType: tier.commissionType,
        commissionValue: tier.commissionValue,
        isActive: active,
        sortOrder: tier.sortOrder,
      });
      void loadTiers();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare.commission_save_error"));
    } finally {
      setBusyId(null);
    }
  };

  const handleDelete = async (tierId: string) => {
    setBusyId(tierId);
    try {
      await deleteCounterCommissionTierSupabase(tierId);
      toast.success(t("gare.commission_deleted"));
      void loadTiers();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare.commission_delete_error"));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <PercentIcon className="w-4 h-4" />
          {t("gare.commission_title")}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">{t("gare.commission_desc")}</p>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label>{t("gare.commission_role_scope")}</Label>
            <Select
              value={draft.roleScope}
              onValueChange={(v) => setDraft((prev) => ({ ...prev, roleScope: v as DraftTier["roleScope"] }))}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="vendeur_gare">{t("gare.commission_scope_gare")}</SelectItem>
                <SelectItem value="vendeur">{t("gare.commission_scope_company")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("gare.commission_type")}</Label>
            <Select
              value={draft.commissionType}
              onValueChange={(v) =>
                setDraft((prev) => ({ ...prev, commissionType: v as DraftTier["commissionType"] }))
              }
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="percentage">{t("gare.commission_type_pct")}</SelectItem>
                <SelectItem value="fixed">{t("gare.commission_type_fixed")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("gare.commission_min")}</Label>
            <Input
              type="number"
              min={0}
              value={draft.minAmount}
              onChange={(e) => setDraft((prev) => ({ ...prev, minAmount: e.target.value }))}
            />
          </div>
          <div className="space-y-1.5">
            <Label>{t("gare.commission_max")}</Label>
            <Input
              type="number"
              min={0}
              placeholder={t("gare.commission_max_open")}
              value={draft.maxAmount}
              onChange={(e) => setDraft((prev) => ({ ...prev, maxAmount: e.target.value }))}
            />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label>{t("gare.commission_value")}</Label>
            <Input
              type="number"
              min={0}
              value={draft.commissionValue}
              onChange={(e) => setDraft((prev) => ({ ...prev, commissionValue: e.target.value }))}
            />
          </div>
        </div>

        <Button type="button" onClick={() => void handleCreate()} disabled={saving}>
          <PlusIcon className="w-4 h-4 mr-1.5" />
          {saving ? t("gare.commission_saving") : t("gare.commission_add_btn")}
        </Button>

        {tiers === undefined ? (
          <Skeleton className="h-20 rounded-lg" />
        ) : tiers.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("gare.commission_empty")}</p>
        ) : (
          <div className="space-y-2">
            {tiers.map((tier) => (
              <div
                key={tier.id}
                className="flex items-center justify-between gap-3 rounded-lg border p-3"
              >
                <div className="min-w-0">
                  <p className="text-sm font-medium truncate">{formatTierLabel(tier, t)}</p>
                  {!tier.isActive ? (
                    <p className="text-xs text-muted-foreground">{t("gare.commission_inactive")}</p>
                  ) : null}
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <Switch
                    checked={tier.isActive}
                    disabled={busyId === tier.id}
                    onCheckedChange={(checked) => void handleToggle(tier, checked)}
                  />
                  <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="text-destructive"
                    disabled={busyId === tier.id}
                    onClick={() => void handleDelete(tier.id)}
                  >
                    <TrashIcon className="w-4 h-4" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
