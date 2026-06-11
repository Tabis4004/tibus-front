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
  type GareManagerRevenueSummary,
} from "@/lib/supabase/gare-manager-revenue.ts";

function fmt(amount: number, currency: string) {
  return `${amount.toLocaleString()} ${currency}`;
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
    return <Skeleton className="h-48 w-full rounded-xl" />;
  }

  const { totals, currency, rows } = summary;
  const activeRows = rows.filter(
    (row) =>
      row.sharePct > 0
      || row.counterSalesGmv > 0
      || row.reservationShareTotal > 0,
  );

  return (
    <Card>
      <CardHeader className="pb-3 flex flex-row items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center">
            <HandCoinsIcon className="w-4 h-4 text-primary" />
          </div>
          <div>
            <CardTitle className="text-base">{t("gare_revenue.title")}</CardTitle>
            <p className="text-xs text-muted-foreground mt-0.5">{t("gare_revenue.subtitle")}</p>
          </div>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="shrink-0"
          disabled={refreshing}
          onClick={() => void load(true)}
        >
          <RefreshCwIcon className={`w-4 h-4 ${refreshing ? "animate-spin" : ""}`} />
        </Button>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
          <div className="rounded-lg border bg-muted/40 p-3 text-center">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide">
              {t("gare_revenue.counter_gmv")}
            </p>
            <p className="font-black text-sm mt-1">{fmt(totals.counterSalesGmv, currency)}</p>
            <p className="text-[10px] text-muted-foreground mt-1">
              {t("gare_revenue.counter_collected")}: {fmt(totals.counterShareCollected, currency)}
            </p>
          </div>
          <div className="rounded-lg border bg-muted/40 p-3 text-center">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide">
              {t("gare_revenue.reservation_commission")}
            </p>
            <p className="font-black text-sm mt-1">{fmt(totals.reservationShareTotal, currency)}</p>
          </div>
          <div className="rounded-lg border bg-emerald-500/10 p-3 text-center">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide">
              {t("gare_revenue.already_paid")}
            </p>
            <p className="font-black text-sm mt-1 text-emerald-700 dark:text-emerald-400">
              {fmt(totals.paidTotal, currency)}
            </p>
          </div>
          <div className="rounded-lg border bg-amber-500/10 p-3 text-center">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide">
              {t("gare_revenue.to_pay")}
            </p>
            <p className="font-black text-sm mt-1 text-amber-700 dark:text-amber-400">
              {fmt(totals.pendingTotal, currency)}
            </p>
          </div>
        </div>

        <p className="text-xs text-muted-foreground">{t("gare_revenue.logic_hint")}</p>

        {activeRows.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-4">{t("gare_revenue.empty")}</p>
        ) : (
          <div className="space-y-2">
            {activeRows.map((row) => (
              <div
                key={row.gareId}
                className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-lg border p-3"
              >
                <div className="min-w-0">
                  <p className="font-semibold text-sm truncate">{row.gareName}</p>
                  <p className="text-xs text-muted-foreground">
                    {row.managerName ?? t("gare_revenue.no_manager")} · {row.sharePct}%
                  </p>
                  <p className="text-xs text-muted-foreground mt-1">
                    {t("gare_revenue.row_counter")}: {fmt(row.counterShareCollected, currency)} ·{" "}
                    {t("gare_revenue.row_reservation_due")}: {fmt(row.pendingTotal, currency)}
                  </p>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <Badge variant="secondary">
                    {fmt(row.reservationShareTotal, currency)} {t("gare_revenue.reservation_badge")}
                  </Badge>
                  {row.pendingTotal > 0 && (
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={payingGareId === row.gareId}
                      onClick={() => void handleMarkPaid(row.gareId)}
                    >
                      {t("gare_revenue.mark_paid")}
                    </Button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
