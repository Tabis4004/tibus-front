import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { GiftIcon, SaveIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getCompanyLoyaltySettingsSupabase,
  upsertCompanyLoyaltySettingsSupabase,
  type CompanyLoyaltySettings,
} from "@/lib/supabase/loyalty.ts";

export default function LoyaltySettings({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const { t: tc } = useTranslation("common");
  const [settings, setSettings] = useState<CompanyLoyaltySettings | undefined>(undefined);
  const [saving, setSaving] = useState(false);

  const load = () => {
    setSettings(undefined);
    void getCompanyLoyaltySettingsSupabase(companyId)
      .then(setSettings)
      .catch((err) => toast.error(err instanceof Error ? err.message : t("loyalty.load_error")));
  };

  useEffect(() => {
    load();
  }, [companyId]);

  const update = <K extends keyof CompanyLoyaltySettings>(key: K, value: CompanyLoyaltySettings[K]) => {
    setSettings((prev) => (prev ? { ...prev, [key]: value } : prev));
  };

  const handleSave = async () => {
    if (!settings) return;
    setSaving(true);
    try {
      await upsertCompanyLoyaltySettingsSupabase(companyId, {
        isActive: settings.isActive,
        spendUnitAmount: settings.spendUnitAmount,
        pointsPerSpendUnit: settings.pointsPerSpendUnit,
        discountPerPoint: settings.discountPerPoint,
        minRedeemPoints: settings.minRedeemPoints,
        maxRedeemPercent: settings.maxRedeemPercent,
      });
      toast.success(t("loyalty.saved"));
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("loyalty.save_error"));
    } finally {
      setSaving(false);
    }
  };

  if (settings === undefined) {
    return <Skeleton className="h-72 w-full" />;
  }

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-extrabold">{t("loyalty.title")}</h1>
        <p className="text-sm text-muted-foreground mt-1">{t("loyalty.desc")}</p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <GiftIcon className="w-4 h-4" />
            {t("loyalty.settings_title")}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <Label>{t("loyalty.active_label")}</Label>
              <p className="text-xs text-muted-foreground">{t("loyalty.active_desc")}</p>
            </div>
            <Switch checked={settings.isActive} onCheckedChange={(v) => update("isActive", v)} />
          </div>

          <div className="grid sm:grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label>{t("loyalty.spend_unit")}</Label>
              <Input
                type="number"
                min={1}
                value={settings.spendUnitAmount}
                onChange={(e) => update("spendUnitAmount", Number(e.target.value) || 0)}
              />
              <p className="text-xs text-muted-foreground">{t("loyalty.spend_unit_hint")}</p>
            </div>
            <div className="space-y-1.5">
              <Label>{t("loyalty.points_per_unit")}</Label>
              <Input
                type="number"
                min={1}
                value={settings.pointsPerSpendUnit}
                onChange={(e) => update("pointsPerSpendUnit", Number(e.target.value) || 0)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("loyalty.discount_per_point")}</Label>
              <Input
                type="number"
                min={1}
                value={settings.discountPerPoint}
                onChange={(e) => update("discountPerPoint", Number(e.target.value) || 0)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("loyalty.min_redeem")}</Label>
              <Input
                type="number"
                min={0}
                value={settings.minRedeemPoints}
                onChange={(e) => update("minRedeemPoints", Number(e.target.value) || 0)}
              />
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label>{t("loyalty.max_percent")}</Label>
              <Input
                type="number"
                min={0}
                max={100}
                value={settings.maxRedeemPercent}
                onChange={(e) => update("maxRedeemPercent", Number(e.target.value) || 0)}
              />
            </div>
          </div>

          <Button className="cursor-pointer gap-2" disabled={saving} onClick={() => void handleSave()}>
            <SaveIcon className="w-4 h-4" />
            {saving ? t("loyalty.saving") : tc("buttons.save")}
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
