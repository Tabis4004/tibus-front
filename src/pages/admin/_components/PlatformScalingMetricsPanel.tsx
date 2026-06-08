import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  ActivityIcon,
  DownloadIcon,
  PrinterIcon,
  RefreshCwIcon,
  ShieldAlertIcon,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Progress } from "@/components/ui/progress.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { cn } from "@/lib/utils.ts";
import {
  buildMetricsExportPayload,
  formatBytes,
  getPlatformScalingMetricsSupabase,
  SCALING_TIER_ROWS,
  type PlatformScalingMetrics,
  type ScalingTierId,
} from "@/lib/supabase/platform-metrics.ts";

const TIER_THRESHOLDS: Record<
  ScalingTierId,
  { sellers: number; avgDaily: number; connections: number }
> = {
  demarrage: { sellers: 20, avgDaily: 500, connections: 30 },
  croissance: { sellers: 100, avgDaily: 3000, connections: 80 },
  fort_trafic: { sellers: 300, avgDaily: 15000, connections: 200 },
  national: { sellers: 800, avgDaily: 50000, connections: 600 },
  tres_haut_volume: { sellers: 1000, avgDaily: 60000, connections: 800 },
};

function pct(value: number, max: number): number {
  if (max <= 0) return 0;
  return Math.min(100, Math.round((value / max) * 100));
}

function downloadJson(filename: string, payload: unknown) {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

type MetricGaugeProps = {
  label: string;
  value: number;
  max: number;
  suffix?: string;
};

function MetricGauge({ label, value, max, suffix = "" }: MetricGaugeProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2 text-sm">
        <span className="text-muted-foreground">{label}</span>
        <span className="font-medium tabular-nums">
          {value.toLocaleString()}
          {suffix}
          <span className="text-muted-foreground font-normal"> / {max.toLocaleString()}</span>
        </span>
      </div>
      <Progress value={pct(value, max)} className="h-2" />
    </div>
  );
}

export default function PlatformScalingMetricsPanel() {
  const { t } = useTranslation("admin");
  const printRef = useRef<HTMLDivElement>(null);
  const [metrics, setMetrics] = useState<PlatformScalingMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    void getPlatformScalingMetricsSupabase()
      .then(setMetrics)
      .catch((err) => {
        const message = err instanceof Error ? err.message : t("scaling_metrics.load_error");
        setError(message);
        setMetrics(null);
      })
      .finally(() => setLoading(false));
  }, [t]);

  useEffect(() => {
    load();
  }, [load]);

  const thresholds = useMemo(
    () => (metrics ? TIER_THRESHOLDS[metrics.recommendedTier] : TIER_THRESHOLDS.demarrage),
    [metrics],
  );

  const handleExportJson = () => {
    if (!metrics) return;
    const stamp = new Date().toISOString().slice(0, 10);
    downloadJson(`tibus-scaling-metrics-${stamp}.json`, buildMetricsExportPayload(metrics));
    toast.success(t("scaling_metrics.export_json_done"));
  };

  const handlePrint = () => {
    window.print();
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="pt-6 space-y-3">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-32 w-full" />
          <Skeleton className="h-48 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (error || !metrics) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <ShieldAlertIcon className="w-4 h-4" />
            {t("scaling_metrics.title")}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-destructive">{error ?? t("scaling_metrics.load_error")}</p>
          <p className="text-xs text-muted-foreground">{t("scaling_metrics.migration_hint")}</p>
          <Button type="button" variant="outline" size="sm" onClick={load} className="gap-2">
            <RefreshCwIcon className="w-4 h-4" />
            {t("scaling_metrics.refresh")}
          </Button>
        </CardContent>
      </Card>
    );
  }

  const generatedLabel = new Date(metrics.generatedAt).toLocaleString();

  return (
    <div ref={printRef} className="space-y-6 print:space-y-4">
      <Card className="print:shadow-none print:border">
        <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between print:flex-row">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              <ActivityIcon className="w-4 h-4" />
              {t("scaling_metrics.title")}
            </CardTitle>
            <p className="text-xs text-muted-foreground mt-1">
              {t("scaling_metrics.subtitle", { project: metrics.supabaseProjectRef })}
            </p>
            <p className="text-xs text-muted-foreground">{generatedLabel}</p>
          </div>
          <div className="flex flex-wrap gap-2 print:hidden">
            <Button type="button" variant="outline" size="sm" onClick={load} className="gap-2">
              <RefreshCwIcon className="w-4 h-4" />
              {t("scaling_metrics.refresh")}
            </Button>
            <Button type="button" variant="outline" size="sm" onClick={handleExportJson} className="gap-2">
              <DownloadIcon className="w-4 h-4" />
              {t("scaling_metrics.export_json")}
            </Button>
            <Button type="button" variant="outline" size="sm" onClick={handlePrint} className="gap-2">
              <PrinterIcon className="w-4 h-4" />
              {t("scaling_metrics.export_pdf")}
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="rounded-lg border bg-muted/40 p-4">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm font-medium">{t("scaling_metrics.current_tier")}</span>
              <Badge>{t(`scaling_metrics.tiers.${metrics.recommendedTier}`)}</Badge>
            </div>
            <p className="text-xs text-muted-foreground mt-2">
              {t(`scaling_metrics.reco.${metrics.recommendedTier}`)}
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <StatTile label={t("scaling_metrics.stats.sellers")} value={metrics.sellersTotal} />
            <StatTile label={t("scaling_metrics.stats.tickets_today")} value={metrics.ticketsToday} />
            <StatTile
              label={t("scaling_metrics.stats.avg_daily_30d")}
              value={metrics.avgTicketsPerDay30d}
            />
            <StatTile
              label={t("scaling_metrics.stats.est_connections")}
              value={metrics.estimatedPeakConnections}
            />
            <StatTile label={t("total_users")} value={metrics.usersTotal} />
            <StatTile label={t("total_companies")} value={metrics.companiesActive} />
            <StatTile label={t("scaling_metrics.stats.tickets_30d")} value={metrics.tickets30d} />
            <StatTile
              label={t("scaling_metrics.stats.db_size")}
              value={formatBytes(metrics.databaseSizeBytes)}
              raw
            />
          </div>

          <div className="space-y-4">
            <h3 className="text-sm font-semibold">{t("scaling_metrics.gauges_title")}</h3>
            <MetricGauge
              label={t("scaling_metrics.stats.sellers")}
              value={metrics.sellersTotal}
              max={thresholds.sellers}
            />
            <MetricGauge
              label={t("scaling_metrics.stats.avg_daily_30d")}
              value={metrics.avgTicketsPerDay30d}
              max={thresholds.avgDaily}
            />
            <MetricGauge
              label={t("scaling_metrics.stats.est_connections")}
              value={metrics.estimatedPeakConnections}
              max={thresholds.connections}
            />
          </div>
        </CardContent>
      </Card>

      <Card className="print:shadow-none print:border">
        <CardHeader>
          <CardTitle className="text-base">{t("scaling_metrics.grid_title")}</CardTitle>
          <p className="text-xs text-muted-foreground">{t("scaling_metrics.grid_desc")}</p>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="py-2 pr-3 font-medium">{t("scaling_metrics.col.scenario")}</th>
                <th className="py-2 pr-3 font-medium">{t("scaling_metrics.col.sellers")}</th>
                <th className="py-2 pr-3 font-medium">{t("scaling_metrics.col.reservations")}</th>
                <th className="py-2 pr-3 font-medium">{t("scaling_metrics.col.connections")}</th>
                <th className="py-2 pr-3 font-medium">{t("scaling_metrics.col.reco")}</th>
                <th className="py-2 font-medium">{t("scaling_metrics.col.cost")}</th>
              </tr>
            </thead>
            <tbody>
              {SCALING_TIER_ROWS.map((row) => (
                <tr
                  key={row.id}
                  className={cn(
                    "border-b last:border-0",
                    row.id === metrics.recommendedTier && "bg-primary/5",
                  )}
                >
                  <td className="py-2 pr-3 font-medium">
                    {t(row.labelKey)}
                    {row.id === metrics.recommendedTier && (
                      <Badge variant="secondary" className="ml-2">
                        {t("scaling_metrics.you_are_here")}
                      </Badge>
                    )}
                  </td>
                  <td className="py-2 pr-3 tabular-nums">{row.sellersRange}</td>
                  <td className="py-2 pr-3 tabular-nums">{row.reservationsPerDay}</td>
                  <td className="py-2 pr-3 tabular-nums">{row.connectionsPeak}</td>
                  <td className="py-2 pr-3">{t(row.recommendationKey)}</td>
                  <td className="py-2 tabular-nums">{row.costRange}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>

      <Card className="print:hidden">
        <CardHeader>
          <CardTitle className="text-base">{t("scaling_metrics.canvas_export_title")}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-muted-foreground">
          <p>{t("scaling_metrics.canvas_export_step1")}</p>
          <p>{t("scaling_metrics.canvas_export_step2")}</p>
          <p>{t("scaling_metrics.canvas_export_step3")}</p>
          <p>{t("scaling_metrics.canvas_export_step4")}</p>
        </CardContent>
      </Card>
    </div>
  );
}

function StatTile({
  label,
  value,
  raw = false,
}: {
  label: string;
  value: number | string;
  raw?: boolean;
}) {
  return (
    <div className="rounded-lg border p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="text-xl font-bold tabular-nums mt-1">
        {raw ? value : typeof value === "number" ? value.toLocaleString() : value}
      </p>
    </div>
  );
}
