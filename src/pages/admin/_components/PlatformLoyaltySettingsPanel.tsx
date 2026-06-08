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
  getPlatformLoyaltySettingsSupabase,
  upsertPlatformLoyaltySettingsSupabase,
  type PlatformLoyaltySettings,
} from "@/lib/supabase/platform-loyalty.ts";

export default function PlatformLoyaltySettingsPanel() {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [settings, setSettings] = useState<PlatformLoyaltySettings | undefined>(undefined);
  const [saving, setSaving] = useState(false);

  const load = () => {
    setSettings(undefined);
    void getPlatformLoyaltySettingsSupabase()
      .then(setSettings)
      .catch((err) => toast.error(err instanceof Error ? err.message : "Chargement impossible"));
  };

  useEffect(() => {
    load();
  }, []);

  const update = <K extends keyof PlatformLoyaltySettings>(key: K, value: PlatformLoyaltySettings[K]) => {
    setSettings((prev) => (prev ? { ...prev, [key]: value } : prev));
  };

  const handleSave = async () => {
    if (!settings) return;
    setSaving(true);
    try {
      await upsertPlatformLoyaltySettingsSupabase({
        isActive: settings.isActive,
        referralSignupReferrerPoints: settings.referralSignupReferrerPoints,
        referralSignupNewUserPoints: settings.referralSignupNewUserPoints,
        referralSharePoints: settings.referralSharePoints,
        referralShareDailyLimit: settings.referralShareDailyLimit,
        spendUnitAmount: settings.spendUnitAmount,
        pointsPerSpendUnit: settings.pointsPerSpendUnit,
        discountPerPoint: settings.discountPerPoint,
        minRedeemPoints: settings.minRedeemPoints,
        maxRedeemPercent: settings.maxRedeemPercent,
      });
      toast.success(t("platform_loyalty.saved", { defaultValue: "Barèmes plateforme enregistrés" }));
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Enregistrement impossible");
    } finally {
      setSaving(false);
    }
  };

  if (settings === undefined) {
    return <Skeleton className="h-72 w-full" />;
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <GiftIcon className="w-4 h-4" />
          {t("platform_loyalty.title", { defaultValue: "Fidélité plateforme Tibus" })}
        </CardTitle>
        <p className="text-xs text-muted-foreground">
          {t("platform_loyalty.desc", {
            defaultValue: "Parrainage, partage de lien et points sur les réservations voyageurs.",
          })}
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between gap-3">
          <Label>{t("platform_loyalty.active", { defaultValue: "Programme actif" })}</Label>
          <Switch checked={settings.isActive} onCheckedChange={(v) => update("isActive", v)} />
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.referral_referrer_points", { defaultValue: "Points parrain (inscription)" })}</Label>
            <Input type="number" min={0} value={settings.referralSignupReferrerPoints} onChange={(e) => update("referralSignupReferrerPoints", Number(e.target.value) || 0)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.referral_new_user_points", { defaultValue: "Points filleul (inscription)" })}</Label>
            <Input type="number" min={0} value={settings.referralSignupNewUserPoints} onChange={(e) => update("referralSignupNewUserPoints", Number(e.target.value) || 0)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.share_points", { defaultValue: "Points par partage de lien" })}</Label>
            <Input type="number" min={0} value={settings.referralSharePoints} onChange={(e) => update("referralSharePoints", Number(e.target.value) || 0)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.share_daily", { defaultValue: "Partages max / jour" })}</Label>
            <Input type="number" min={1} value={settings.referralShareDailyLimit} onChange={(e) => update("referralShareDailyLimit", Number(e.target.value) || 1)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.booking_unit", { defaultValue: "Montant billet (XOF) pour gagner" })}</Label>
            <Input type="number" min={1} value={settings.spendUnitAmount} onChange={(e) => update("spendUnitAmount", Number(e.target.value) || 0)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.booking_points", { defaultValue: "Points gagnés par tranche" })}</Label>
            <Input type="number" min={1} value={settings.pointsPerSpendUnit} onChange={(e) => update("pointsPerSpendUnit", Number(e.target.value) || 0)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.discount_per_point", { defaultValue: "Réduction par point (XOF)" })}</Label>
            <Input type="number" min={1} value={settings.discountPerPoint} onChange={(e) => update("discountPerPoint", Number(e.target.value) || 0)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.min_redeem", { defaultValue: "Minimum utilisation" })}</Label>
            <Input type="number" min={0} value={settings.minRedeemPoints} onChange={(e) => update("minRedeemPoints", Number(e.target.value) || 0)} />
          </div>
          <div className="space-y-1.5">
            <Label>{t("platform_loyalty.max_percent", { defaultValue: "Plafond % du billet" })}</Label>
            <Input type="number" min={0} max={100} value={settings.maxRedeemPercent} onChange={(e) => update("maxRedeemPercent", Number(e.target.value) || 0)} />
          </div>
        </div>

        <Button className="cursor-pointer gap-2" disabled={saving} onClick={() => void handleSave()}>
          <SaveIcon className="w-4 h-4" />
          {saving ? "…" : tc("buttons.save")}
        </Button>
      </CardContent>
    </Card>
  );
}
