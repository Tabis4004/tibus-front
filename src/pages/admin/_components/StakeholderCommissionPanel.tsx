import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  CheckIcon,
  HistoryIcon,
  PercentIcon,
  RefreshCwIcon,
  WalletIcon,
  XIcon,
} from "lucide-react";
import { toast } from "sonner";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  STAKEHOLDER_ROLE_ORDER,
  confirmStakeholderCommissionSettlementSupabase,
  initiateStakeholderCommissionSettlementSupabase,
  listStakeholderCommissionBalancesSupabase,
  listStakeholderCommissionSettlementHistorySupabase,
  listStakeholderCommissionSettingsSupabase,
  previewStakeholderCommissionAttributionSupabase,
  rejectStakeholderCommissionSettlementSupabase,
  upsertStakeholderCommissionSettingSupabase,
  type StakeholderCommissionBalance,
  type StakeholderCommissionBaseType,
  type StakeholderCommissionSetting,
  type StakeholderCommissionSettlement,
  type StakeholderRole,
} from "@/lib/supabase/stakeholder-commissions.ts";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import { parseFeeInputOrZero } from "@/lib/fee-input.ts";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
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
import { cn } from "@/lib/utils.ts";

type CountryOption = { id: string; name: string };

const BASE_TYPES: StakeholderCommissionBaseType[] = [
  "gateway_amount",
  "total_amount",
  "platform_net",
];

function formatMoney(value: number, currency: string) {
  return `${value.toLocaleString(undefined, { maximumFractionDigits: 0 })} ${currency}`;
}

function statusVariant(status: StakeholderCommissionSettlement["status"]) {
  if (status === "confirmed") return "default" as const;
  if (status === "pending_confirmation") return "secondary" as const;
  if (status === "rejected") return "destructive" as const;
  return "outline" as const;
}

export default function StakeholderCommissionPanel({
  countries,
  embedded = false,
}: {
  countries: CountryOption[];
  embedded?: boolean;
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const appUser = useAppUser();
  const isSuperAdmin = appUser.isSuperAdmin;
  const isCountryAdmin = appUser.roles.includes("admin_pays");

  const defaultCountryId = useMemo(() => {
    if (isSuperAdmin) return countries[0]?.id ?? "";
    return appUser.profile?.countryId ?? countries[0]?.id ?? "";
  }, [appUser.profile?.countryId, countries, isSuperAdmin]);

  const [countryId, setCountryId] = useState(defaultCountryId);
  const [settingsScope, setSettingsScope] = useState<"global" | "country">("country");
  const [settings, setSettings] = useState<StakeholderCommissionSetting[] | undefined>(undefined);
  const [rateDrafts, setRateDrafts] = useState<Record<string, string>>({});
  const [baseDrafts, setBaseDrafts] = useState<Record<string, StakeholderCommissionBaseType>>({});
  const [balances, setBalances] = useState<StakeholderCommissionBalance[] | undefined>(undefined);
  const [history, setHistory] = useState<StakeholderCommissionSettlement[] | undefined>(undefined);
  const [previewGateway, setPreviewGateway] = useState("10000");
  const [preview, setPreview] = useState<Awaited<
    ReturnType<typeof previewStakeholderCommissionAttributionSupabase>
  > | null>(null);
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [savingSettings, setSavingSettings] = useState(false);

  useEffect(() => {
    if (defaultCountryId && !countryId) setCountryId(defaultCountryId);
  }, [countryId, defaultCountryId]);

  const effectiveSettingsCountryId =
    settingsScope === "global" && isSuperAdmin ? null : countryId || null;

  const loadSettings = useCallback(() => {
    setSettings(undefined);
    void listStakeholderCommissionSettingsSupabase(effectiveSettingsCountryId)
      .then((rows) => {
        setSettings(rows);
        const rates: Record<string, string> = {};
        const bases: Record<string, StakeholderCommissionBaseType> = {};
        for (const row of rows) {
          rates[row.stakeholderRole] = String(row.rate);
          bases[row.stakeholderRole] = row.baseType;
        }
        setRateDrafts(rates);
        setBaseDrafts(bases);
      })
      .catch((err) => {
        setSettings([]);
        toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.load_error"));
      });
  }, [effectiveSettingsCountryId, t]);

  const loadBalances = useCallback(() => {
    if (!countryId && !isCountryAdmin) {
      setBalances([]);
      return;
    }
    setBalances(undefined);
    void listStakeholderCommissionBalancesSupabase(countryId || null)
      .then(setBalances)
      .catch((err) => {
        setBalances([]);
        toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.load_error"));
      });
  }, [countryId, isCountryAdmin, t]);

  const loadHistory = useCallback(() => {
    setHistory(undefined);
    void listStakeholderCommissionSettlementHistorySupabase({
      countryId: countryId || null,
      limit: 50,
    })
      .then(setHistory)
      .catch((err) => {
        setHistory([]);
        toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.history_error"));
      });
  }, [countryId, t]);

  const reloadAll = useCallback(() => {
    loadSettings();
    loadBalances();
    loadHistory();
  }, [loadBalances, loadHistory, loadSettings]);

  useEffect(() => {
    reloadAll();
  }, [reloadAll, countryId, settingsScope]);

  const totalRate = useMemo(
    () => (settings ?? []).reduce((sum, row) => sum + (row.isActive ? row.rate : 0), 0),
    [settings],
  );

  const pendingSettlements = useMemo(
    () => (history ?? []).filter((row) => row.status === "pending_confirmation"),
    [history],
  );

  const handleSaveSetting = async (role: StakeholderRole) => {
    const rate = parseFeeInputOrZero(rateDrafts[role] ?? "0");
    if (rate == null) {
      toast.error(t("stakeholder_commissions.invalid_rate"));
      return;
    }

    setSavingSettings(true);
    try {
      const scope = settingsScope === "global" && isSuperAdmin ? "global" : "country";
      await upsertStakeholderCommissionSettingSupabase({
        scope,
        countryId: scope === "country" ? countryId : null,
        stakeholderRole: role,
        rate,
        baseType: baseDrafts[role] ?? "gateway_amount",
      });
      toast.success(t("stakeholder_commissions.settings_saved"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "update",
        summary: `Taux ${role} → ${rate}% (${scope})`,
        metadata: { role, rate, scope, countryId },
      });
      loadSettings();
      loadBalances();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.save_error"));
    } finally {
      setSavingSettings(false);
    }
  };

  const handlePreview = async () => {
    const gatewayAmount = parseFeeInputOrZero(previewGateway);
    if (gatewayAmount == null || !countryId) return;
    try {
      const result = await previewStakeholderCommissionAttributionSupabase({
        gatewayAmount,
        countryId,
      });
      setPreview(result);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.preview_error"));
    }
  };

  const handleInitiatePayment = async (row: StakeholderCommissionBalance) => {
    const key = `pay:${row.stakeholderRole}:${row.beneficiaryUserId ?? "platform"}`;
    setBusyKey(key);
    try {
      await initiateStakeholderCommissionSettlementSupabase({
        countryId: row.countryId,
        stakeholderRole: row.stakeholderRole,
        beneficiaryUserId: row.beneficiaryUserId,
      });
      toast.success(t("stakeholder_commissions.payment_initiated"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "create",
        summary: `Paiement initié ${row.stakeholderRole} ${row.beneficiaryName ?? "plateforme"}`,
        metadata: {
          countryId: row.countryId,
          role: row.stakeholderRole,
          beneficiaryUserId: row.beneficiaryUserId,
          amount: row.balanceDue,
        },
      });
      loadBalances();
      loadHistory();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.payment_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const handleConfirm = async (settlement: StakeholderCommissionSettlement) => {
    setBusyKey(settlement.id);
    try {
      await confirmStakeholderCommissionSettlementSupabase(settlement.id);
      toast.success(t("stakeholder_commissions.payment_confirmed"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "update",
        summary: `Paiement confirmé ${settlement.stakeholderRole}`,
        metadata: { settlementId: settlement.id },
      });
      loadBalances();
      loadHistory();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.confirm_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const handleReject = async (settlement: StakeholderCommissionSettlement) => {
    setBusyKey(settlement.id);
    try {
      await rejectStakeholderCommissionSettlementSupabase(settlement.id);
      toast.success(t("stakeholder_commissions.payment_rejected"));
      loadBalances();
      loadHistory();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.reject_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const canConfirmSettlement = (settlement: StakeholderCommissionSettlement) => {
    if (settlement.status !== "pending_confirmation") return false;
    if (isSuperAdmin) return true;
    return settlement.beneficiaryUserId === appUser.profile?.id;
  };

  return (
    <div className={cn("space-y-4", embedded && "p-0")}>
      <div className="flex flex-wrap items-end gap-3">
        <div className="space-y-1.5 min-w-[200px]">
          <Label>{t("stakeholder_commissions.country")}</Label>
          <Select
            value={countryId}
            onValueChange={setCountryId}
            disabled={!isSuperAdmin}
          >
            <SelectTrigger>
              <SelectValue placeholder={t("commissions.select_country", { defaultValue: "Pays" })} />
            </SelectTrigger>
            <SelectContent>
              {countries.map((country) => (
                <SelectItem key={country.id} value={country.id}>
                  {country.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <Button variant="outline" size="sm" className="gap-2" onClick={reloadAll}>
          <RefreshCwIcon className="w-4 h-4" />
          {t("stakeholder_commissions.refresh")}
        </Button>
      </div>

      <p className="text-xs text-muted-foreground">{t("stakeholder_commissions.realtime_hint")}</p>

      {isSuperAdmin && (
        <div className="rounded-lg border p-3 space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2 text-sm font-medium">
              <PercentIcon className="w-4 h-4" />
              {t("stakeholder_commissions.rates_title")}
            </div>
            <Select
              value={settingsScope}
              onValueChange={(value) => setSettingsScope(value as "global" | "country")}
            >
              <SelectTrigger className="w-[160px] h-8">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="country">{t("stakeholder_commissions.scope_country")}</SelectItem>
                <SelectItem value="global">{t("stakeholder_commissions.scope_global")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <p className="text-xs text-muted-foreground">{t("stakeholder_commissions.rates_desc")}</p>
          {totalRate > 100 && (
            <p className="text-xs text-destructive">{t("stakeholder_commissions.rate_overflow", { total: totalRate })}</p>
          )}
          {settings === undefined ? (
            <Skeleton className="h-24 w-full" />
          ) : (
            <div className="overflow-x-auto rounded-lg border">
              <table className="min-w-full text-sm">
                <thead className="bg-muted/60 text-left">
                  <tr>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_rate")}</th>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_base")}</th>
                    <th className="px-3 py-2" />
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {STAKEHOLDER_ROLE_ORDER.map((role) => (
                    <tr key={role}>
                      <td className="px-3 py-2">{t(`stakeholder_commissions.roles.${role}`)}</td>
                      <td className="px-3 py-2">
                        <Input
                          className="h-8 w-24"
                          value={rateDrafts[role] ?? "0"}
                          onChange={(e) =>
                            setRateDrafts((current) => ({ ...current, [role]: e.target.value }))
                          }
                        />
                      </td>
                      <td className="px-3 py-2">
                        <Select
                          value={baseDrafts[role] ?? "gateway_amount"}
                          onValueChange={(value) =>
                            setBaseDrafts((current) => ({
                              ...current,
                              [role]: value as StakeholderCommissionBaseType,
                            }))
                          }
                        >
                          <SelectTrigger className="h-8 w-[180px]">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {BASE_TYPES.map((baseType) => (
                              <SelectItem key={baseType} value={baseType}>
                                {t(`stakeholder_commissions.base_types.${baseType}`)}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </td>
                      <td className="px-3 py-2">
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={savingSettings}
                          onClick={() => void handleSaveSetting(role)}
                        >
                          {tc("buttons.save")}
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <div className="flex flex-wrap items-end gap-2 pt-1">
            <div className="space-y-1">
              <Label>{t("stakeholder_commissions.preview_gateway")}</Label>
              <Input
                className="h-8 w-32"
                value={previewGateway}
                onChange={(e) => setPreviewGateway(e.target.value)}
              />
            </div>
            <Button size="sm" variant="outline" onClick={() => void handlePreview()}>
              {t("stakeholder_commissions.preview")}
            </Button>
          </div>
          {preview && (
            <div className="text-xs text-muted-foreground grid gap-1 md:grid-cols-2">
              {preview.items.map((item) => (
                <div key={item.stakeholderRole}>
                  {t(`stakeholder_commissions.roles.${item.stakeholderRole}`)}: {formatMoney(item.amount, "XOF")} ({item.rate}%)
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      <div className="rounded-lg border p-3 space-y-3">
        <div className="flex items-center gap-2 text-sm font-medium">
          <WalletIcon className="w-4 h-4" />
          {t("stakeholder_commissions.balances_title")}
        </div>
        {balances === undefined ? (
          <Skeleton className="h-40 w-full" />
        ) : balances.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("stakeholder_commissions.no_balances")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_user")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_rate")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_earned")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_paid")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_pending")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_balance")}</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y">
                {balances.map((row) => {
                  const rowKey = `${row.stakeholderRole}:${row.beneficiaryUserId ?? "platform"}`;
                  return (
                    <tr key={rowKey}>
                      <td className="px-3 py-2">{t(`stakeholder_commissions.roles.${row.stakeholderRole}`)}</td>
                      <td className="px-3 py-2">{row.beneficiaryName ?? t("stakeholder_commissions.platform_pool")}</td>
                      <td className="px-3 py-2">{row.rate}%</td>
                      <td className="px-3 py-2 tabular-nums">{formatMoney(row.earnedAmount, row.currency)}</td>
                      <td className="px-3 py-2 tabular-nums text-emerald-700">{formatMoney(row.paidAmount, row.currency)}</td>
                      <td className="px-3 py-2 tabular-nums text-amber-700">{formatMoney(row.pendingAmount, row.currency)}</td>
                      <td className="px-3 py-2 tabular-nums font-medium">{formatMoney(row.balanceDue, row.currency)}</td>
                      <td className="px-3 py-2">
                        {isSuperAdmin && row.balanceDue > 0 && row.pendingAmount <= 0 && (
                          <Button
                            size="sm"
                            disabled={busyKey === `pay:${row.stakeholderRole}:${row.beneficiaryUserId ?? "platform"}`}
                            onClick={() => void handleInitiatePayment(row)}
                          >
                            {t("stakeholder_commissions.mark_paid")}
                          </Button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="rounded-lg border p-3 space-y-3">
        <div className="flex items-center gap-2 text-sm font-medium">
          <HistoryIcon className="w-4 h-4" />
          {t("stakeholder_commissions.history_title")}
        </div>

        {pendingSettlements.length > 0 && (
          <div className="space-y-2">
            <p className="text-xs font-medium text-muted-foreground">{t("stakeholder_commissions.pending_validation")}</p>
            {pendingSettlements.map((settlement) => (
              <div key={settlement.id} className="flex flex-wrap items-center justify-between gap-2 rounded-md border p-2 text-sm">
                <div>
                  <span className="font-medium">{t(`stakeholder_commissions.roles.${settlement.stakeholderRole}`)}</span>
                  {" · "}
                  {settlement.beneficiaryName ?? t("stakeholder_commissions.platform_pool")}
                  {" · "}
                  {formatMoney(settlement.amount, settlement.currency)}
                </div>
                {canConfirmSettlement(settlement) && (
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      className="gap-1"
                      disabled={busyKey === settlement.id}
                      onClick={() => void handleConfirm(settlement)}
                    >
                      <CheckIcon className="w-3 h-3" />
                      {t("stakeholder_commissions.confirm_payment")}
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      className="gap-1"
                      disabled={busyKey === settlement.id}
                      onClick={() => void handleReject(settlement)}
                    >
                      <XIcon className="w-3 h-3" />
                      {t("stakeholder_commissions.reject_payment")}
                    </Button>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}

        {history === undefined ? (
          <Skeleton className="h-32 w-full" />
        ) : history.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("stakeholder_commissions.no_history")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_date")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_user")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_amount")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_status")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_initiated_by")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_validated_by")}</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {history.map((row) => (
                  <tr key={row.id}>
                    <td className="px-3 py-2 whitespace-nowrap">{new Date(row.initiatedAt).toLocaleString()}</td>
                    <td className="px-3 py-2">{t(`stakeholder_commissions.roles.${row.stakeholderRole}`)}</td>
                    <td className="px-3 py-2">{row.beneficiaryName ?? t("stakeholder_commissions.platform_pool")}</td>
                    <td className="px-3 py-2 tabular-nums">{formatMoney(row.amount, row.currency)}</td>
                    <td className="px-3 py-2">
                      <Badge variant={statusVariant(row.status)}>
                        {t(`stakeholder_commissions.status.${row.status}`)}
                      </Badge>
                    </td>
                    <td className="px-3 py-2">{row.initiatedByName ?? "—"}</td>
                    <td className="px-3 py-2">{row.confirmedByName ?? row.rejectedByName ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
