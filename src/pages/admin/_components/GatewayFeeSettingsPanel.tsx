import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { PlusIcon, SettingsIcon, TrashIcon } from "lucide-react";
import { toast } from "sonner";
import type { PaymentGateway, PaymentMethod } from "@/config/commission.ts";
import {
  deleteGatewayPaymentFeeSupabase,
  listGatewayPaymentFeesSupabase,
  upsertGatewayPaymentFeeSupabase,
  type GatewayPaymentFeeSetting,
} from "@/lib/supabase/payment-fees.ts";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  formatFeeInput,
  parseFeeInputOrZero,
  parseOptionalFeeInput,
} from "@/lib/fee-input.ts";

const GATEWAYS: PaymentGateway[] = [
  "fedapay",
  "geniuspay",
  "cinetpay",
  "paystack",
  "paiementpro",
];

const METHODS: PaymentMethod[] = [
  "mobile_money",
  "card",
  "bank_transfer",
  "wallet",
];

const NETWORKS = [
  "orange",
  "mtn",
  "moov",
  "wave",
  "default",
] as const;

type CountryOption = { id: string; name: string };

export default function GatewayFeeSettingsPanel({
  countries,
}: {
  countries: CountryOption[];
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [rows, setRows] = useState<GatewayPaymentFeeSetting[] | undefined>(undefined);
  const [saving, setSaving] = useState(false);
  const [draft, setDraft] = useState({
    gateway: "fedapay" as PaymentGateway,
    countryId: "",
    method: "mobile_money" as PaymentMethod,
    network: "orange",
    yPercent: "",
    zPercent: "",
    fFixed: "",
  });

  const load = () => {
    setRows(undefined);
    void listGatewayPaymentFeesSupabase()
      .then(setRows)
      .catch((err) => {
        setRows([]);
        toast.error(err instanceof Error ? err.message : t("gateway_fees.load_error"));
      });
  };

  useEffect(() => {
    load();
  }, []);

  const handleCreate = async () => {
    if (!draft.countryId) {
      toast.error(t("gateway_fees.country_required"));
      return;
    }
    const yPercent = parseFeeInputOrZero(draft.yPercent);
    if (yPercent == null) {
      toast.error(t("gateway_fees.invalid_y"));
      return;
    }

    setSaving(true);
    try {
      await upsertGatewayPaymentFeeSupabase({
        gateway: draft.gateway,
        countryId: draft.countryId,
        method: draft.method,
        network: draft.network,
        yPercent,
        zPercent: parseOptionalFeeInput(draft.zPercent),
        fFixed: parseOptionalFeeInput(draft.fFixed),
      });
      toast.success(t("gateway_fees.saved"));
      load();
    } catch (err) {
      const message = err instanceof Error ? err.message : t("gateway_fees.save_error");
      toast.error(message);
    } finally {
      setSaving(false);
    }
  };

  const handleUpdate = async (row: GatewayPaymentFeeSetting, patch: Partial<GatewayPaymentFeeSetting>) => {
    setSaving(true);
    try {
      await upsertGatewayPaymentFeeSupabase({
        gateway: row.gateway,
        countryId: row.countryId,
        method: row.method,
        network: row.network,
        yPercent: patch.yPercent ?? row.yPercent,
        zPercent: patch.zPercent !== undefined ? patch.zPercent : row.zPercent,
        fFixed: patch.fFixed !== undefined ? patch.fFixed : row.fFixed,
        isActive: patch.isActive ?? row.isActive,
      });
      toast.success(t("gateway_fees.saved"));
      load();
    } catch (err) {
      const message = err instanceof Error ? err.message : t("gateway_fees.save_error");
      toast.error(message);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (row: GatewayPaymentFeeSetting) => {
    setSaving(true);
    try {
      await deleteGatewayPaymentFeeSupabase(row.id);
      toast.success(t("gateway_fees.deleted"));
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gateway_fees.save_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card className="border-dashed">
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <SettingsIcon className="w-4 h-4" />
          {t("gateway_fees.title")}
        </CardTitle>
        <p className="text-sm text-muted-foreground">
          {t("gateway_fees.desc_db")}
        </p>
        <p className="text-xs text-muted-foreground">
          {t("gateway_fees.network_hint")}
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="rounded-lg bg-muted/50 p-3 text-sm">
          <p className="font-medium">{t("gateway_fees.formula")}</p>
          <p className="text-muted-foreground mt-1">{t("gateway_fees.margin_source")}</p>
        </div>

        <div className="grid gap-3 md:grid-cols-7">
          <div className="space-y-1.5">
            <Label>{t("gateway_fees.col_gateway")}</Label>
            <Select
              value={draft.gateway}
              onValueChange={(value) =>
                setDraft((current) => ({ ...current, gateway: value as PaymentGateway }))
              }
            >
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {GATEWAYS.map((gateway) => (
                  <SelectItem key={gateway} value={gateway}>{gateway}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5 md:col-span-2">
            <Label>{t("gateway_fees.col_country")}</Label>
            <Select
              value={draft.countryId}
              onValueChange={(value) => setDraft((current) => ({ ...current, countryId: value }))}
            >
              <SelectTrigger><SelectValue placeholder={t("commissions.select_country", { defaultValue: "Pays" })} /></SelectTrigger>
              <SelectContent>
                {countries.map((country) => (
                  <SelectItem key={country.id} value={country.id}>{country.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("gateway_fees.col_method")}</Label>
            <Select
              value={draft.method}
              onValueChange={(value) =>
                setDraft((current) => ({ ...current, method: value as PaymentMethod }))
              }
            >
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {METHODS.map((method) => (
                  <SelectItem key={method} value={method}>{method}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("gateway_fees.col_network")}</Label>
            <Select
              value={draft.network}
              onValueChange={(value) => setDraft((current) => ({ ...current, network: value }))}
            >
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {NETWORKS.map((network) => (
                  <SelectItem key={network} value={network}>{network}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Y (%)</Label>
            <Input
              placeholder="1.8"
              value={draft.yPercent}
              onChange={(e) => setDraft((c) => ({ ...c, yPercent: e.target.value }))}
            />
          </div>
          <div className="space-y-1.5">
            <Label>Z (%)</Label>
            <Input
              placeholder={t("gateway_fees.optional_placeholder")}
              value={draft.zPercent}
              onChange={(e) => setDraft((c) => ({ ...c, zPercent: e.target.value }))}
            />
          </div>
          <div className="space-y-1.5">
            <Label>F</Label>
            <Input
              placeholder={t("gateway_fees.optional_placeholder")}
              value={draft.fFixed}
              onChange={(e) => setDraft((c) => ({ ...c, fFixed: e.target.value }))}
            />
          </div>
          <div className="md:col-span-7">
            <Button onClick={handleCreate} disabled={saving} className="gap-2">
              <PlusIcon className="w-4 h-4" />
              {t("gateway_fees.add")}
            </Button>
          </div>
        </div>

        {rows === undefined ? (
          <Skeleton className="h-40 w-full" />
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("gateway_fees.empty")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">{t("gateway_fees.col_gateway")}</th>
                  <th className="px-3 py-2">{t("gateway_fees.col_country")}</th>
                  <th className="px-3 py-2">{t("gateway_fees.col_method")}</th>
                  <th className="px-3 py-2">{t("gateway_fees.col_network")}</th>
                  <th className="px-3 py-2">Y (%)</th>
                  <th className="px-3 py-2">Z (%)</th>
                  <th className="px-3 py-2">F</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((row) => (
                  <GatewayFeeRow
                    key={row.id}
                    row={row}
                    saving={saving}
                    onSave={handleUpdate}
                    onDelete={handleDelete}
                    saveLabel={tc("buttons.save")}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function GatewayFeeRow({
  row,
  saving,
  onSave,
  onDelete,
  saveLabel,
}: {
  row: GatewayPaymentFeeSetting;
  saving: boolean;
  onSave: (row: GatewayPaymentFeeSetting, patch: Partial<GatewayPaymentFeeSetting>) => void;
  onDelete: (row: GatewayPaymentFeeSetting) => void;
  saveLabel: string;
}) {
  const [yPercent, setYPercent] = useState(formatFeeInput(row.yPercent));
  const [zPercent, setZPercent] = useState(formatFeeInput(row.zPercent));
  const [fFixed, setFFixed] = useState(formatFeeInput(row.fFixed));

  return (
    <tr>
      <td className="px-3 py-2 capitalize">{row.gateway}</td>
      <td className="px-3 py-2">{row.countryName}</td>
      <td className="px-3 py-2">{row.method}</td>
      <td className="px-3 py-2 capitalize">{row.network}</td>
      <td className="px-3 py-2">
        <Input className="h-8 w-20" value={yPercent} onChange={(e) => setYPercent(e.target.value)} />
      </td>
      <td className="px-3 py-2">
        <Input className="h-8 w-20" value={zPercent} onChange={(e) => setZPercent(e.target.value)} />
      </td>
      <td className="px-3 py-2">
        <Input className="h-8 w-20" value={fFixed} onChange={(e) => setFFixed(e.target.value)} />
      </td>
      <td className="px-3 py-2">
        <div className="flex gap-2">
          <Button
            size="sm"
            variant="secondary"
            disabled={saving}
            onClick={() => {
              const parsedY = parseFeeInputOrZero(yPercent);
              if (parsedY == null) return;
              onSave(row, {
                yPercent: parsedY,
                zPercent: parseOptionalFeeInput(zPercent),
                fFixed: parseOptionalFeeInput(fFixed),
              });
            }}
          >
            {saveLabel}
          </Button>
          <Button size="sm" variant="outline" disabled={saving} onClick={() => onDelete(row)}>
            <TrashIcon className="w-4 h-4" />
          </Button>
        </div>
      </td>
    </tr>
  );
}
