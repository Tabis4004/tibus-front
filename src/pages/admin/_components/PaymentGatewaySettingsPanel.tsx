import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { CreditCardIcon } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import {
  getActivePaymentGatewaySupabase,
  setActivePaymentGatewaySupabase,
  type ActivePaymentGateway,
} from "@/lib/supabase/payment-gateway.ts";

export default function PaymentGatewaySettingsPanel() {
  const { t } = useTranslation("admin");
  const [gateway, setGateway] = useState<ActivePaymentGateway>("fedapay");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = () => {
    setLoading(true);
    void getActivePaymentGatewaySupabase()
      .then((state) => setGateway(state.gateway))
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("payment_gateway.load_error"));
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, []);

  const handleToggle = (checked: boolean) => {
    const next: ActivePaymentGateway = checked ? "geniuspay" : "fedapay";
    setSaving(true);
    void setActivePaymentGatewaySupabase(next)
      .then((state) => {
        setGateway(state.gateway);
        toast.success(
          t("payment_gateway.saved", {
            gateway: t(`payment_gateway.options.${state.gateway}`),
          }),
        );
      })
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("payment_gateway.save_error"));
        load();
      })
      .finally(() => setSaving(false));
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="pt-6">
          <Skeleton className="h-16 w-full" />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <CreditCardIcon className="w-4 h-4" />
          {t("payment_gateway.title")}
        </CardTitle>
        <p className="text-xs text-muted-foreground mt-1">{t("payment_gateway.desc")}</p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-col gap-4 rounded-lg border p-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <Label htmlFor="gateway-switch">{t("payment_gateway.active_label")}</Label>
              <Badge variant={gateway === "geniuspay" ? "default" : "secondary"}>
                {t(`payment_gateway.options.${gateway}`)}
              </Badge>
            </div>
            <p className="text-xs text-muted-foreground">
              {gateway === "geniuspay"
                ? t("payment_gateway.geniuspay_hint")
                : t("payment_gateway.fedapay_hint")}
            </p>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-xs text-muted-foreground">FedaPay</span>
            <Switch
              id="gateway-switch"
              checked={gateway === "geniuspay"}
              disabled={saving}
              onCheckedChange={handleToggle}
            />
            <span className="text-xs font-medium">GeniusPay</span>
          </div>
        </div>
        <p className="text-xs text-muted-foreground">{t("payment_gateway.fees_hint")}</p>
      </CardContent>
    </Card>
  );
}
