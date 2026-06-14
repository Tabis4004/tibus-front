import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { PercentIcon, RefreshCwIcon, WalletIcon } from "lucide-react";
import { toast } from "sonner";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  confirmSellerCommissionPaymentSupabase,
  getSellerCommissionDashboardSupabase,
  requestSellerCommissionPaymentSupabase,
  type SellerCommissionDashboard,
} from "@/lib/supabase/accounting.ts";
import { listPlatformUsersForAdminSupabase, type PlatformAdminUserRow } from "@/lib/supabase/admin-users.ts";
import { supabase } from "@/lib/supabase";
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

type SellerOption = { id: string; label: string };

type PaymentRequestRow = {
  id: string;
  amount: number;
  currency: string;
  bookingCount: number;
  requestedAt: string;
};

function monthStartIso() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString();
}

function formatMoney(value: number, currency: string) {
  return `${value.toLocaleString(undefined, { maximumFractionDigits: 0 })} ${currency}`;
}

function statusLabel(status: string) {
  switch (status) {
    case "paid":
      return "Payé";
    case "payment_requested":
      return "Demande de paiement";
    case "pending":
      return "Encours non payé";
    default:
      return status;
  }
}

export default function SellerCommissionDashboardPanel({
  embedded = false,
  sellerUserId,
  allowPaymentRequest = false,
}: {
  embedded?: boolean;
  sellerUserId?: string | null;
  allowPaymentRequest?: boolean;
}) {
  const { t } = useTranslation("admin");
  const appUser = useAppUser();
  const isSuperAdmin = appUser.isSuperAdmin;
  const [dateFrom, setDateFrom] = useState(monthStartIso().slice(0, 10));
  const [dateTo, setDateTo] = useState(new Date().toISOString().slice(0, 10));
  const [selectedSellerId, setSelectedSellerId] = useState(sellerUserId ?? "__self");
  const [sellerOptions, setSellerOptions] = useState<SellerOption[]>([]);
  const [dashboard, setDashboard] = useState<SellerCommissionDashboard | undefined>(undefined);
  const [requests, setRequests] = useState<PaymentRequestRow[] | undefined>(undefined);
  const [busy, setBusy] = useState(false);

  const effectiveSellerId = useMemo(() => {
    if (sellerUserId) return sellerUserId;
    if (isSuperAdmin && selectedSellerId !== "__self") return selectedSellerId;
    return null;
  }, [isSuperAdmin, selectedSellerId, sellerUserId]);

  const loadSellerOptions = useCallback(async () => {
    if (!isSuperAdmin || sellerUserId) return;
    try {
      const users = await listPlatformUsersForAdminSupabase(500);
      setSellerOptions(
        users
          .filter((user: PlatformAdminUserRow) =>
            user.roles.some((role: string) =>
              ["vendeur_independant", "vendeur_master", "vendeur_reseau"].includes(role),
            ),
          )
          .map((user: PlatformAdminUserRow) => ({
            id: user.id,
            label: `${user.firstName} ${user.lastName}`.trim() || user.email || user.username,
          })),
      );
    } catch {
      setSellerOptions([]);
    }
  }, [isSuperAdmin, sellerUserId]);

  const loadRequests = useCallback(async () => {
    if (!isSuperAdmin) {
      setRequests([]);
      return;
    }
    const { data, error } = await supabase
      .from("SellerCommissionPaymentRequests")
      .select("id, amount, currency, bookingCount, requestedAt")
      .eq("status", "pending_confirmation")
      .order("requestedAt", { ascending: false });
    if (error) {
      setRequests([]);
      return;
    }
    setRequests(
      (data ?? []).map((row) => ({
        id: row.id as string,
        amount: Number(row.amount ?? 0),
        currency: String(row.currency ?? "XOF"),
        bookingCount: Number(row.bookingCount ?? 0),
        requestedAt: String(row.requestedAt),
      })),
    );
  }, [isSuperAdmin]);

  const loadDashboard = useCallback(async () => {
    setDashboard(undefined);
    try {
      const from = dateFrom ? new Date(`${dateFrom}T00:00:00`).toISOString() : null;
      const to = dateTo ? new Date(`${dateTo}T23:59:59`).toISOString() : null;
      setDashboard(
        await getSellerCommissionDashboardSupabase({
          dateFrom: from,
          dateTo: to,
          sellerUserId: effectiveSellerId,
        }),
      );
    } catch (err) {
      setDashboard(undefined);
      toast.error(err instanceof Error ? err.message : "Impossible de charger les commissions vendeur.");
    }
  }, [dateFrom, dateTo, effectiveSellerId]);

  const reloadAll = useCallback(() => {
    void loadDashboard();
    void loadRequests();
  }, [loadDashboard, loadRequests]);

  useEffect(() => {
    void loadSellerOptions();
  }, [loadSellerOptions]);

  useEffect(() => {
    reloadAll();
  }, [reloadAll]);

  return (
    <div className={embedded ? "space-y-4" : "space-y-4 p-0"}>
      <div className="flex flex-wrap items-end gap-3">
        <div className="space-y-1.5">
          <Label>{t("seller_commissions.period_from", { defaultValue: "Du" })}</Label>
          <Input type="date" className="h-9 w-[160px]" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
        </div>
        <div className="space-y-1.5">
          <Label>{t("seller_commissions.period_to", { defaultValue: "Au" })}</Label>
          <Input type="date" className="h-9 w-[160px]" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
        </div>
        {isSuperAdmin && !sellerUserId ? (
          <div className="space-y-1.5 min-w-[220px]">
            <Label>{t("seller_commissions.seller", { defaultValue: "Vendeur" })}</Label>
            <Select value={selectedSellerId} onValueChange={setSelectedSellerId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="__self">{t("seller_commissions.all_sellers", { defaultValue: "Mon compte" })}</SelectItem>
                {sellerOptions.map((option) => (
                  <SelectItem key={option.id} value={option.id}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        ) : null}
        <Button variant="outline" size="sm" className="gap-2" onClick={reloadAll}>
          <RefreshCwIcon className="w-4 h-4" />
          {t("stakeholder_commissions.refresh", { defaultValue: "Actualiser" })}
        </Button>
      </div>

      {dashboard === undefined ? (
        <Skeleton className="h-36 w-full" />
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard label={t("seller_commissions.total", { defaultValue: "Total" })} value={dashboard.totalAmount} currency={dashboard.currency} />
            <StatCard label={t("seller_commissions.pending", { defaultValue: "Encours non payé" })} value={dashboard.pendingAmount} currency={dashboard.currency} />
            <StatCard label={t("seller_commissions.requested", { defaultValue: "Demande de paiement" })} value={dashboard.paymentRequestedAmount} currency={dashboard.currency} />
            <StatCard label={t("seller_commissions.paid", { defaultValue: "Payé" })} value={dashboard.paidAmount} currency={dashboard.currency} />
          </div>
          <p className="text-xs text-muted-foreground">{dashboard.ticketCount} vente(s) tiers sur la période</p>
          {allowPaymentRequest && dashboard.pendingAmount > 0 ? (
            <Button
              size="sm"
              disabled={busy}
              onClick={() => {
                setBusy(true);
                const from = dateFrom ? new Date(`${dateFrom}T00:00:00`).toISOString() : null;
                const to = dateTo ? new Date(`${dateTo}T23:59:59`).toISOString() : null;
                void requestSellerCommissionPaymentSupabase({ dateFrom: from, dateTo: to })
                  .then(() => {
                    toast.success(t("seller_commissions.request_sent", { defaultValue: "Demande de paiement envoyée." }));
                    reloadAll();
                  })
                  .catch((err) => toast.error(err instanceof Error ? err.message : "Demande impossible."))
                  .finally(() => setBusy(false));
              }}
            >
              <WalletIcon className="w-4 h-4 mr-1.5" />
              {t("seller_commissions.request_payment", { defaultValue: "Demander le paiement" })}
            </Button>
          ) : null}
        </>
      )}

      {isSuperAdmin && requests && requests.length > 0 ? (
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-sm font-medium">{t("seller_commissions.pending_requests", { defaultValue: "Demandes en attente" })}</p>
          <div className="divide-y">
            {requests.map((req) => (
              <div key={req.id} className="py-2 flex items-center justify-between gap-3 text-sm">
                <div>
                  <p className="font-medium">{formatMoney(req.amount, req.currency)}</p>
                  <p className="text-xs text-muted-foreground">
                    {req.bookingCount} billet(s) · {new Date(req.requestedAt).toLocaleString()}
                  </p>
                </div>
                <Button
                  size="sm"
                  disabled={busy}
                  onClick={() => {
                    setBusy(true);
                    void confirmSellerCommissionPaymentSupabase(req.id)
                      .then(() => {
                        toast.success(t("seller_commissions.confirmed", { defaultValue: "Paiement confirmé." }));
                        reloadAll();
                      })
                      .catch((err) => toast.error(err instanceof Error ? err.message : "Confirmation impossible."))
                      .finally(() => setBusy(false));
                  }}
                >
                  {t("seller_commissions.confirm_payment", { defaultValue: "Confirmer payé" })}
                </Button>
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {dashboard && dashboard.entries.length > 0 ? (
        <div className="overflow-x-auto rounded-lg border">
          <table className="min-w-full text-sm">
            <thead className="bg-muted/60 text-left">
              <tr>
                <th className="px-3 py-2">{t("commissions.company", { defaultValue: "Compagnie" })}</th>
                <th className="px-3 py-2">Réf.</th>
                <th className="px-3 py-2">{t("seller_commissions.amount", { defaultValue: "Montant" })}</th>
                <th className="px-3 py-2">{t("seller_commissions.status", { defaultValue: "Statut" })}</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {dashboard.entries.map((entry) => (
                <tr key={entry.bookingId}>
                  <td className="px-3 py-2">{entry.companyName}</td>
                  <td className="px-3 py-2 text-muted-foreground">{entry.reference}</td>
                  <td className="px-3 py-2 tabular-nums">{formatMoney(entry.commissionAmount, entry.currency)}</td>
                  <td className="px-3 py-2">
                    <Badge variant="secondary">{statusLabel(entry.commissionStatus)}</Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : dashboard ? (
        <p className="text-sm text-muted-foreground">
          {t("seller_commissions.no_entries", { defaultValue: "Aucune commission sur cette période." })}
        </p>
      ) : null}
    </div>
  );
}

function StatCard({ label, value, currency }: { label: string; value: number; currency: string }) {
  return (
    <div className="rounded-lg border bg-background p-3">
      <div className="flex items-center gap-2 text-xs text-muted-foreground mb-1">
        <PercentIcon className="w-3.5 h-3.5" />
        {label}
      </div>
      <p className="text-xl font-black tabular-nums">{formatMoney(value, currency)}</p>
    </div>
  );
}
