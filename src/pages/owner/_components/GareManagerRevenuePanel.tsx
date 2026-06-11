import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { HandCoinsIcon, RefreshCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getGareManagerCounterRevenueSummarySupabase,
  markGareManagerSharesPaidSupabase,
  type GareManagerRevenueRow,
  type GareManagerRevenueSummary,
} from "@/lib/supabase/gare-manager-revenue.ts";

const POLL_MS = 20_000;

function fmt(amount: number, currency: string) {
  return `${amount.toLocaleString()} ${currency}`;
}

function amountCell(amount: number, currency: string, highlight?: "pending" | "paid") {
  const className =
    highlight === "pending"
      ? "font-semibold text-amber-700 dark:text-amber-400"
      : highlight === "paid"
        ? "font-semibold text-emerald-700 dark:text-emerald-400"
        : "font-medium";

  return <span className={className}>{fmt(amount, currency)}</span>;
}

export default function GareManagerRevenuePanel({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const [summary, setSummary] = useState<GareManagerRevenueSummary | undefined>(undefined);
  const [refreshing, setRefreshing] = useState(false);
  const [payingGareId, setPayingGareId] = useState<string | null>(null);

  const load = useCallback(
    async (silent = false) => {
      if (!silent) setSummary(undefined);
      else setRefreshing(true);
      try {
        setSummary(await getGareManagerCounterRevenueSummarySupabase(companyId));
      } catch (err) {
        toast.error(err instanceof Error ? err.message : t("gare_revenue.load_error"));
        setSummary({
          currency: "XOF",
          rows: [],
          totals: {
            counterSalesGmv: 0,
            counterShareCollected: 0,
            reservationShareTotal: 0,
            paidTotal: 0,
            pendingTotal: 0,
          },
        });
      } finally {
        setRefreshing(false);
      }
    },
    [companyId, t],
  );

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => void load(true), POLL_MS);
    return () => window.clearInterval(timer);
  }, [load]);

  const handleMarkPaid = async (gareId: string) => {
    setPayingGareId(gareId);
    try {
      const count = await markGareManagerSharesPaidSupabase(gareId);
      toast.success(t("gare_revenue.marked_paid", { count }));
      await load(true);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare_revenue.pay_error"));
    } finally {
      setPayingGareId(null);
    }
  };

  if (!summary) {
    return <Skeleton className="h-56 w-full rounded-xl" />;
  }

  const { totals, currency, rows } = summary;
  const visibleRows = rows.filter(
    (row) =>
      row.sharePct > 0
      || row.sharePctReservation > 0
      || row.managerUserId
      || row.counterSalesGmv > 0
      || row.reservationShareTotal > 0,
  );

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <CardTitle className="text-base flex items-center gap-2">
            <HandCoinsIcon className="w-4 h-4" />
            {t("gare_revenue.title")}
            {totals.pendingTotal > 0 ? (
              <Badge variant="outline" className="text-amber-700 border-amber-300">
                {fmt(totals.pendingTotal, currency)} {t("gare_revenue.to_pay")}
              </Badge>
            ) : null}
          </CardTitle>
          <Button
            size="sm"
            variant="outline"
            className="h-8 cursor-pointer"
            disabled={refreshing}
            onClick={() => void load(true)}
          >
            <RefreshCwIcon className={`w-3.5 h-3.5 mr-1.5 ${refreshing ? "animate-spin" : ""}`} />
            {t("gare_revenue.refresh")}
          </Button>
        </div>
        <p className="text-xs text-muted-foreground mt-1">{t("gare_revenue.logic_hint")}</p>
      </CardHeader>
      <CardContent>
        {visibleRows.length === 0 ? (
          <p className="text-sm text-muted-foreground py-6 text-center">{t("gare_revenue.empty")}</p>
        ) : (
          <div className="overflow-x-auto rounded-xl border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2 whitespace-nowrap">{t("gare_revenue.col_station")}</th>
                  <th className="px-3 py-2 whitespace-nowrap">{t("gare_revenue.col_manager")}</th>
                  <th className="px-3 py-2 text-right whitespace-nowrap">{t("gare_revenue.col_pct_counter")}</th>
                  <th className="px-3 py-2 text-right whitespace-nowrap">{t("gare_revenue.col_pct_reservation")}</th>
                  <th className="px-3 py-2 text-right whitespace-nowrap">{t("gare_revenue.col_counter_gmv")}</th>
                  <th className="px-3 py-2 text-right whitespace-nowrap">{t("gare_revenue.col_counter_collected")}</th>
                  <th className="px-3 py-2 text-right whitespace-nowrap">{t("gare_revenue.col_reservation")}</th>
                  <th className="px-3 py-2 text-right whitespace-nowrap">{t("gare_revenue.col_paid")}</th>
                  <th className="px-3 py-2 text-right whitespace-nowrap">{t("gare_revenue.col_pending")}</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y">
                {visibleRows.map((row) => (
                  <GareRevenueTableRow
                    key={row.gareId}
                    row={row}
                    currency={currency}
                    paying={payingGareId === row.gareId}
                    onMarkPaid={() => void handleMarkPaid(row.gareId)}
                    t={t}
                  />
                ))}
              </tbody>
              <tfoot className="bg-muted/30 font-semibold border-t">
                <tr>
                  <td className="px-3 py-2" colSpan={4}>
                    {t("gare_revenue.total_row")}
                  </td>
                  <td className="px-3 py-2 text-right">{amountCell(totals.counterSalesGmv, currency)}</td>
                  <td className="px-3 py-2 text-right">
                    {amountCell(totals.counterShareCollected, currency)}
                  </td>
                  <td className="px-3 py-2 text-right">
                    {amountCell(totals.reservationShareTotal, currency)}
                  </td>
                  <td className="px-3 py-2 text-right">{amountCell(totals.paidTotal, currency, "paid")}</td>
                  <td className="px-3 py-2 text-right">
                    {amountCell(totals.pendingTotal, currency, "pending")}
                  </td>
                  <td className="px-3 py-2" />
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function GareRevenueTableRow({
  row,
  currency,
  paying,
  onMarkPaid,
  t,
}: {
  row: GareManagerRevenueRow;
  currency: string;
  paying: boolean;
  onMarkPaid: () => void;
  t: (key: string) => string;
}) {
  return (
    <tr className="hover:bg-muted/30 transition-colors">
      <td className="px-3 py-2 font-medium whitespace-nowrap">{row.gareName}</td>
      <td className="px-3 py-2 text-muted-foreground whitespace-nowrap">
        {row.managerName ?? t("gare_revenue.no_manager")}
      </td>
      <td className="px-3 py-2 text-right">{row.sharePct}%</td>
      <td className="px-3 py-2 text-right">{row.sharePctReservation}%</td>
      <td className="px-3 py-2 text-right">{amountCell(row.counterSalesGmv, currency)}</td>
      <td className="px-3 py-2 text-right">{amountCell(row.counterShareCollected, currency)}</td>
      <td className="px-3 py-2 text-right">{amountCell(row.reservationShareTotal, currency)}</td>
      <td className="px-3 py-2 text-right">{amountCell(row.paidTotal, currency, "paid")}</td>
      <td className="px-3 py-2 text-right">{amountCell(row.pendingTotal, currency, "pending")}</td>
      <td className="px-3 py-2 whitespace-nowrap">
        {row.pendingTotal > 0 ? (
          <Button size="sm" variant="outline" className="h-8 cursor-pointer" disabled={paying} onClick={onMarkPaid}>
            {t("gare_revenue.mark_paid")}
          </Button>
        ) : (
          <span className="text-xs text-muted-foreground">—</span>
        )}
      </td>
    </tr>
  );
}
