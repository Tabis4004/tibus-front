import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { RefreshCwIcon, WalletIcon } from "lucide-react";
import { toast } from "sonner";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  confirmStakeholderCommissionSettlementSupabase,
  getMyStakeholderCommissionDashboardSupabase,
  initiateStakeholderCommissionSettlementSupabase,
  listStakeholderCommissionSettlementHistorySupabase,
  rejectStakeholderCommissionSettlementSupabase,
  uploadStakeholderPaymentProof,
  type StakeholderCommissionBalance,
  type StakeholderCommissionSettlement,
} from "@/lib/supabase/stakeholder-commissions.ts";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import StakeholderSettlementApprovalFields from "./StakeholderSettlementApprovalFields.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";

function formatMoney(value: number, currency: string) {
  return `${value.toLocaleString(undefined, { maximumFractionDigits: 0 })} ${currency}`;
}

export default function StakeholderPayoutDashboardPanel({
  embedded = false,
  countryId,
}: {
  embedded?: boolean;
  countryId?: string | null;
}) {
  const { t } = useTranslation("admin");
  const appUser = useAppUser();
  const [balances, setBalances] = useState<StakeholderCommissionBalance[] | undefined>(undefined);
  const [pendingApprovals, setPendingApprovals] = useState<
    StakeholderCommissionSettlement[] | undefined
  >(undefined);
  const [canApprove, setCanApprove] = useState(false);
  const [busyKey, setBusyKey] = useState<string | null>(null);

  const loadDashboard = useCallback(async () => {
    setBalances(undefined);
    try {
      const dashboard = await getMyStakeholderCommissionDashboardSupabase(countryId ?? null);
      setBalances(dashboard.balances);
      setCanApprove(dashboard.canApprove);
    } catch (err) {
      setBalances([]);
      toast.error(
        err instanceof Error
          ? err.message
          : t("stakeholder_commissions.dashboard_load_error", {
              defaultValue: "Impossible de charger vos commissions plateforme.",
            }),
      );
    }
  }, [countryId, t]);

  const loadPendingApprovals = useCallback(async () => {
    if (!canApprove && !appUser.isSuperAdmin && !appUser.roles.includes("admin_pays")) {
      setPendingApprovals([]);
      return;
    }
    setPendingApprovals(undefined);
    try {
      const rows = await listStakeholderCommissionSettlementHistorySupabase({
        countryId: countryId ?? null,
        limit: 50,
      });
      setPendingApprovals(rows.filter((row) => row.status === "pending_confirmation"));
    } catch {
      setPendingApprovals([]);
    }
  }, [appUser.isSuperAdmin, appUser.roles, canApprove, countryId]);

  useEffect(() => {
    void loadDashboard();
  }, [loadDashboard]);

  useEffect(() => {
    void loadPendingApprovals();
  }, [loadPendingApprovals, canApprove]);

  const myUserId = appUser.profile?.id;

  const canRequestForRow = useCallback(
    (row: StakeholderCommissionBalance) => {
      if (row.pendingAmount > 0) return false;
      if (row.balanceDue <= 0) return false;
      if (row.balanceDue < row.minimumPayout) return false;
      if (appUser.isSuperAdmin || appUser.roles.includes("admin_pays")) return true;
      return row.beneficiaryUserId === myUserId;
    },
    [appUser.isSuperAdmin, appUser.roles, myUserId],
  );

  const totals = useMemo(() => {
    const earned = (balances ?? []).reduce((sum, row) => sum + row.earnedAmount, 0);
    const due = (balances ?? []).reduce((sum, row) => sum + row.balanceDue, 0);
    const pending = (balances ?? []).reduce((sum, row) => sum + row.pendingAmount, 0);
    const currency = balances?.[0]?.currency ?? "XOF";
    return { earned, due, pending, currency };
  }, [balances]);

  const handleRequest = async (row: StakeholderCommissionBalance) => {
    const key = `req:${row.stakeholderRole}:${row.beneficiaryUserId ?? "x"}`;
    setBusyKey(key);
    try {
      await initiateStakeholderCommissionSettlementSupabase({
        countryId: row.countryId,
        stakeholderRole: row.stakeholderRole,
        beneficiaryUserId: row.beneficiaryUserId,
      });
      toast.success(
        t("stakeholder_commissions.request_submitted", {
          defaultValue: "Demande de paiement soumise.",
        }),
      );
      await loadDashboard();
      await loadPendingApprovals();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.payment_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const handleApprove = async (
    settlement: StakeholderCommissionSettlement,
    input: { approvalNote: string; proofFile: File },
  ) => {
    setBusyKey(settlement.id);
    try {
      const uploaded = await uploadStakeholderPaymentProof(settlement.countryId, input.proofFile);
      await confirmStakeholderCommissionSettlementSupabase({
        settlementId: settlement.id,
        approvalNote: input.approvalNote,
        paymentProofPath: uploaded.path,
        paymentProofFileName: uploaded.fileName,
      });
      toast.success(t("stakeholder_commissions.payment_confirmed"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "update",
        summary: `Paiement approuvé ${settlement.stakeholderRole} — ${settlement.beneficiaryName ?? "—"}`,
        metadata: {
          settlementId: settlement.id,
          amount: settlement.amount,
          approvalNote: input.approvalNote,
          paymentProofPath: uploaded.path,
        },
      });
      await loadDashboard();
      await loadPendingApprovals();
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
      await loadDashboard();
      await loadPendingApprovals();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.reject_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const showPanel =
    (balances?.length ?? 0) > 0 ||
    (pendingApprovals?.length ?? 0) > 0 ||
    canApprove ||
    balances === undefined;

  if (!showPanel && embedded) {
    return null;
  }

  return (
    <div className={embedded ? "space-y-4" : "space-y-4 p-0"}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-medium">
          <WalletIcon className="w-4 h-4" />
          {t("stakeholder_commissions.my_dashboard_title", {
            defaultValue: "Mes commissions plateforme",
          })}
        </div>
        <Button size="sm" variant="outline" className="gap-1" onClick={() => void loadDashboard()}>
          <RefreshCwIcon className="w-3 h-3" />
          {t("stakeholder_commissions.refresh", { defaultValue: "Actualiser" })}
        </Button>
      </div>

      {balances === undefined ? (
        <Skeleton className="h-32 w-full" />
      ) : balances.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {t("stakeholder_commissions.my_dashboard_empty", {
            defaultValue: "Aucune commission stakeholder enregistrée pour votre compte.",
          })}
        </p>
      ) : (
        <>
          <div className="grid gap-2 sm:grid-cols-3">
            <div className="rounded-lg border p-3">
              <p className="text-xs text-muted-foreground">{t("stakeholder_commissions.col_earned")}</p>
              <p className="text-lg font-semibold tabular-nums">
                {formatMoney(totals.earned, totals.currency)}
              </p>
            </div>
            <div className="rounded-lg border p-3">
              <p className="text-xs text-muted-foreground">{t("stakeholder_commissions.col_balance")}</p>
              <p className="text-lg font-semibold tabular-nums">
                {formatMoney(totals.due, totals.currency)}
              </p>
            </div>
            <div className="rounded-lg border p-3">
              <p className="text-xs text-muted-foreground">{t("stakeholder_commissions.col_pending")}</p>
              <p className="text-lg font-semibold tabular-nums text-amber-700">
                {formatMoney(totals.pending, totals.currency)}
              </p>
            </div>
          </div>

          <div className="overflow-x-auto rounded-lg border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_rate")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_earned")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_balance")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_minimum", { defaultValue: "Minimum" })}</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y">
                {balances.map((row) => (
                  <tr key={`${row.stakeholderRole}:${row.beneficiaryUserId ?? "x"}`}>
                    <td className="px-3 py-2">
                      {t(`stakeholder_commissions.roles.${row.stakeholderRole}`)}
                    </td>
                    <td className="px-3 py-2">{row.rate}%</td>
                    <td className="px-3 py-2 tabular-nums">{formatMoney(row.earnedAmount, row.currency)}</td>
                    <td className="px-3 py-2 tabular-nums font-medium">
                      {formatMoney(row.balanceDue, row.currency)}
                    </td>
                    <td className="px-3 py-2 tabular-nums text-muted-foreground">
                      {formatMoney(row.minimumPayout, row.currency)}
                    </td>
                    <td className="px-3 py-2">
                      {canRequestForRow(row) ? (
                        <Button
                          size="sm"
                          disabled={busyKey === `req:${row.stakeholderRole}:${row.beneficiaryUserId ?? "x"}`}
                          onClick={() => void handleRequest(row)}
                        >
                          {t("stakeholder_commissions.request_payout", {
                            defaultValue: "Demander paiement",
                          })}
                        </Button>
                      ) : row.balanceDue > 0 && row.balanceDue < row.minimumPayout ? (
                        <span className="text-xs text-muted-foreground">
                          {t("stakeholder_commissions.below_minimum", {
                            defaultValue: "Sous le minimum",
                          })}
                        </span>
                      ) : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      {canApprove && pendingApprovals && pendingApprovals.length > 0 && (
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-sm font-medium">
            {t("stakeholder_commissions.approval_queue", {
              defaultValue: "Demandes à valider (admin pays)",
            })}
          </p>
          {pendingApprovals.map((settlement) => (
            <div key={settlement.id} className="space-y-2 rounded-md border p-2 text-sm">
              <div>
                <span className="font-medium">
                  {t(`stakeholder_commissions.roles.${settlement.stakeholderRole}`)}
                </span>
                {" · "}
                {settlement.beneficiaryName ?? "—"}
                {" · "}
                {formatMoney(settlement.amount, settlement.currency)}
              </div>
              <StakeholderSettlementApprovalFields
                busy={busyKey === settlement.id}
                onApprove={(input) => handleApprove(settlement, input)}
                onReject={() => handleReject(settlement)}
              />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
