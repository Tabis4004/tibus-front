import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { DownloadIcon, PrinterIcon, RefreshCwIcon, TrendingUpIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { cn } from "@/lib/utils.ts";
import {
  buildInvestorRoiScenarioRows,
  computeInvestorRevenueSharing,
  computeInvestorRoi,
  computeInvestorScenarioProjection,
  DEFAULT_INVESTOR_ROI_INPUTS,
  fmtInvestorMultiple,
  fmtInvestorPercent,
  fmtInvestorXof,
  INVESTOR_CAPITAL,
  INVESTOR_CAPITAL_TABLE,
  INVESTOR_PLAN_ADVANTAGES,
  INVESTOR_PLAN_LEVEE,
  INVESTOR_PLAN_MARKET,
  INVESTOR_PLAN_META,
  INVESTOR_PLAN_REVENUE_MODEL,
  INVESTOR_PLAN_RISKS,
  INVESTOR_PLAN_ROADMAP,
  INVESTOR_SCENARIOS,
  type InvestorRoiInputs,
  type InvestorScenarioId,
} from "@/data/investor-plan-content.ts";
import {
  downloadInvestorPlanJson,
  downloadInvestorPlanPdf,
} from "@/lib/investor-plan-export.ts";
import { getPlatformScalingMetricsSupabase } from "@/lib/supabase/platform-metrics.ts";

function parseOptionalNumber(raw: string): number | null {
  const cleaned = raw.replace(/\s/g, "").replace(",", ".");
  if (!cleaned) return null;
  const value = Number(cleaned);
  return Number.isFinite(value) ? value : null;
}

function PlanTable({ headers, rows }: { headers: string[]; rows: string[][] }) {
  return (
    <div className="overflow-x-auto rounded-lg border">
      <table className="w-full min-w-[640px] text-sm">
        <thead>
          <tr className="border-b bg-muted/40 text-left text-muted-foreground">
            {headers.map((header) => (
              <th key={header} className="px-3 py-2 font-medium whitespace-nowrap">
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={index} className="border-b last:border-0">
              {row.map((cell, cellIndex) => (
                <td key={cellIndex} className="px-3 py-2 align-top tabular-nums">
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const SCENARIO_IDS: InvestorScenarioId[] = ["pessimistic", "realistic", "optimistic"];

export default function InvestorPlanPanel() {
  const { t } = useTranslation("admin");
  const printRef = useRef<HTMLDivElement>(null);
  const [inputs, setInputs] = useState<InvestorRoiInputs>(DEFAULT_INVESTOR_ROI_INPUTS);
  const [loadingLive, setLoadingLive] = useState(true);

  const projection = useMemo(() => computeInvestorScenarioProjection(inputs), [inputs]);
  const roi = useMemo(() => computeInvestorRoi(inputs), [inputs]);
  const revenueSharing = useMemo(() => computeInvestorRevenueSharing(inputs), [inputs]);
  const scenarios = useMemo(() => buildInvestorRoiScenarioRows(), []);
  const roiReady = roi.roi != null;
  const ownerPct = 100 - inputs.investorEquityPct;

  const applyLiveMetrics = useCallback(() => {
    setLoadingLive(true);
    void getPlatformScalingMetricsSupabase()
      .then((metrics) => {
        setInputs((current) => {
          const baseline = INVESTOR_SCENARIOS[current.scenarioId].ticketsMonth[0];
          const liveMonth = Math.max(1, Math.round(metrics.avgTicketsPerDay30d * 30));
          const volumeMultiplierPct =
            baseline > 0 ? Math.round((liveMonth / baseline) * 100) : current.volumeMultiplierPct;
          return { ...current, volumeMultiplierPct };
        });
        toast.success(t("investor_plan.live_sync_done"));
      })
      .catch(() => {
        toast.message(t("investor_plan.live_sync_fallback"));
      })
      .finally(() => setLoadingLive(false));
  }, [t]);

  useEffect(() => {
    applyLiveMetrics();
  }, [applyLiveMetrics]);

  const updateField = <K extends keyof InvestorRoiInputs>(key: K, raw: string) => {
    if (key === "investmentXof") {
      setInputs((current) => ({ ...current, investmentXof: parseOptionalNumber(raw) }));
      return;
    }
    const value = parseOptionalNumber(raw);
    if (value == null) return;
    setInputs((current) => ({ ...current, [key]: value }));
  };

  const setScenario = (scenarioId: InvestorScenarioId) => {
    setInputs((current) => ({ ...current, scenarioId }));
  };

  const handlePrint = () => {
    window.print();
  };

  const handlePdf = () => {
    downloadInvestorPlanPdf(inputs);
    toast.success(t("investor_plan.export_pdf_done"));
  };

  const handleJson = () => {
    downloadInvestorPlanJson(inputs);
    toast.success(t("investor_plan.export_json_done"));
  };

  const leveeEur = Math.round(INVESTOR_PLAN_LEVEE.amountXof / INVESTOR_PLAN_META.eurRate);
  const year5 = projection.years[projection.years.length - 1];

  return (
    <div ref={printRef} className="space-y-6 print:space-y-4">
      <Card className="print:shadow-none print:border">
        <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between print:flex-row">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              <TrendingUpIcon className="w-4 h-4" />
              {t("investor_plan.title")}
            </CardTitle>
            <p className="text-xs text-muted-foreground mt-1">{INVESTOR_PLAN_META.product}</p>
            <p className="text-xs text-muted-foreground">
              {INVESTOR_PLAN_META.url} · {INVESTOR_PLAN_META.date}
            </p>
          </div>
          <div className="flex flex-wrap gap-2 print:hidden">
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="gap-2"
              disabled={loadingLive}
              onClick={applyLiveMetrics}
            >
              <RefreshCwIcon className="w-4 h-4" />
              {t("investor_plan.sync_live")}
            </Button>
            <Button type="button" variant="outline" size="sm" className="gap-2" onClick={handleJson}>
              <DownloadIcon className="w-4 h-4" />
              {t("investor_plan.export_json")}
            </Button>
            <Button type="button" variant="outline" size="sm" className="gap-2" onClick={handlePdf}>
              <DownloadIcon className="w-4 h-4" />
              {t("investor_plan.export_pdf")}
            </Button>
            <Button type="button" variant="outline" size="sm" className="gap-2" onClick={handlePrint}>
              <PrinterIcon className="w-4 h-4" />
              {t("investor_plan.print")}
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="rounded-lg border bg-muted/40 p-4 text-sm leading-relaxed">
            {t("investor_plan.summary", {
              capital: fmtInvestorXof(INVESTOR_CAPITAL.totalXof),
              levee: fmtInvestorXof(INVESTOR_PLAN_LEVEE.amountXof),
              cumul: fmtInvestorXof(projection.cumulativeNet),
              investorShare: fmtInvestorXof(projection.cumulativeInvestorShare),
              scenario: projection.scenario.label,
            })}
          </div>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <StatTile
              label={t("investor_plan.stats.capital")}
              value={fmtInvestorXof(INVESTOR_CAPITAL.totalXof)}
            />
            <StatTile label={t("investor_plan.stats.levee")} value={fmtInvestorXof(INVESTOR_PLAN_LEVEE.amountXof)} />
            <StatTile
              label={t("investor_plan.stats.cumul_net")}
              value={fmtInvestorXof(projection.cumulativeNet)}
            />
            <StatTile
              label={t("investor_plan.stats.investor_share")}
              value={fmtInvestorXof(projection.cumulativeInvestorShare)}
            />
          </div>
        </CardContent>
      </Card>

      <Card className="print:shadow-none print:border">
        <CardHeader>
          <CardTitle className="text-base">{t("investor_plan.simulator_title")}</CardTitle>
          <p className="text-xs text-muted-foreground">{t("investor_plan.simulator_desc")}</p>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="print:hidden space-y-2">
            <Label className="text-xs">{t("investor_plan.fields.scenario")}</Label>
            <div className="flex flex-wrap gap-2">
              {SCENARIO_IDS.map((id) => (
                <Button
                  key={id}
                  type="button"
                  size="sm"
                  variant={inputs.scenarioId === id ? "default" : "outline"}
                  onClick={() => setScenario(id)}
                  className={cn("text-xs", inputs.scenarioId === id && "shadow-sm")}
                >
                  {INVESTOR_SCENARIOS[id].label.replace(" — ", " · ")}
                </Button>
              ))}
            </div>
            <p className="text-xs text-muted-foreground">{projection.scenario.description}</p>
          </div>

          {!roiReady ? (
            <p className="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
              {t("investor_plan.roi_empty")}
            </p>
          ) : (
            <p className="text-sm text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2">
              ROI {fmtInvestorMultiple(roi.roi)} · TRI {fmtInvestorPercent(roi.irr)} · Gain net{" "}
              {fmtInvestorXof(roi.gain)}
            </p>
          )}

          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <StatTile label="ROI" value={fmtInvestorMultiple(roi.roi)} />
            <StatTile label="TRI" value={fmtInvestorPercent(roi.irr)} />
            <StatTile
              label={t("investor_plan.stats.platform_revenue")}
              value={fmtInvestorXof(year5?.tibusRevenue ?? 0)}
            />
            <StatTile label="GMV An 5" value={fmtInvestorXof(year5?.gmv ?? 0)} />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 print:hidden">
            <div className="grid grid-cols-2 gap-3">
              <Field
                label={t("investor_plan.fields.ticket_avg")}
                value={String(inputs.avgTicket)}
                onChange={(v) => updateField("avgTicket", v)}
              />
              <Field
                label={t("investor_plan.fields.take_rate")}
                value={String(inputs.tibusTakeRatePct)}
                onChange={(v) => updateField("tibusTakeRatePct", v)}
              />
              <Field
                label={t("investor_plan.fields.volume_multiplier")}
                value={String(inputs.volumeMultiplierPct)}
                onChange={(v) => updateField("volumeMultiplierPct", v)}
              />
              <Field
                label={t("investor_plan.fields.investment")}
                value={inputs.investmentXof == null ? "" : String(inputs.investmentXof)}
                onChange={(v) => updateField("investmentXof", v)}
                placeholder="6000000"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Field
                label={t("investor_plan.fields.equity")}
                value={String(inputs.investorEquityPct)}
                onChange={(v) => updateField("investorEquityPct", v)}
              />
              <Field
                label={t("investor_plan.fields.owner_equity")}
                value={String(ownerPct)}
                onChange={() => undefined}
                readOnly
              />
              <Field
                label={t("investor_plan.fields.horizon")}
                value={String(inputs.horizonYears)}
                onChange={(v) => updateField("horizonYears", v)}
              />
              <div className="col-span-2 flex items-end">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => setInputs(DEFAULT_INVESTOR_ROI_INPUTS)}
                >
                  {t("investor_plan.reset")}
                </Button>
              </div>
            </div>
          </div>

          <div className="space-y-3">
            <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <h3 className="text-sm font-medium">{t("investor_plan.sections.projection")}</h3>
              <p className="text-xs text-muted-foreground">{t("investor_plan.projection_driver")}</p>
            </div>
            <PlanTable
              headers={[
                t("investor_plan.projection.col.year"),
                t("investor_plan.projection.col.tickets_month"),
                t("investor_plan.projection.col.annual_tickets"),
                t("investor_plan.projection.col.gmv"),
                t("investor_plan.projection.col.platform_revenue"),
                "OPEX",
                t("investor_plan.projection.col.net"),
                t("investor_plan.projection.col.investor_share", { pct: inputs.investorEquityPct }),
                t("investor_plan.projection.col.owner_share", { pct: ownerPct }),
                t("investor_plan.projection.col.note"),
              ]}
              rows={projection.years.map((row) => [
                row.yearLabel,
                row.ticketsMonth.toLocaleString("fr-FR"),
                row.annualTickets.toLocaleString("fr-FR"),
                fmtInvestorXof(row.gmv),
                fmtInvestorXof(row.tibusRevenue),
                fmtInvestorXof(row.opex),
                fmtInvestorXof(row.netResult),
                fmtInvestorXof(row.investorShare),
                fmtInvestorXof(row.ownerShare),
                row.investorNote,
              ])}
            />
          </div>

          <div className="space-y-3 rounded-lg border bg-muted/20 p-4">
            <h3 className="text-sm font-medium">{t("investor_plan.sections.revenue_sharing")}</h3>
            <p className="text-xs text-muted-foreground">{t("investor_plan.revenue_sharing_desc")}</p>
            <p className="text-xs text-muted-foreground italic">{t("investor_plan.stakeholders_note")}</p>

            {projection.years[0] ? (
              <div className="rounded-lg border bg-background p-4 space-y-3">
                <p className="text-xs font-medium">{t("investor_plan.revenue_sharing.example_title")}</p>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 text-sm">
                  <div className="rounded-md border p-3">
                    <p className="text-xs text-muted-foreground">
                      {t("investor_plan.revenue_sharing.col.platform_revenue")} ({projection.years[0].yearLabel})
                    </p>
                    <p className="font-bold tabular-nums mt-1">
                      {fmtInvestorXof(projection.years[0].tibusRevenue)}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1">
                      GMV {fmtInvestorXof(projection.years[0].gmv)} × {inputs.tibusTakeRatePct} %
                    </p>
                  </div>
                  <div className="rounded-md border border-blue-200 bg-blue-50/50 p-3">
                    <p className="text-xs text-muted-foreground">
                      {t("investor_plan.revenue_sharing.investor_block", { pct: inputs.investorEquityPct })}
                    </p>
                    <p className="font-bold tabular-nums mt-1 text-blue-900">
                      {fmtInvestorXof(projection.years[0].investorShare)}
                    </p>
                    <p className="text-xs text-blue-800/80 mt-1">
                      {inputs.investorEquityPct} % × {fmtInvestorXof(projection.years[0].tibusRevenue, "")}
                    </p>
                  </div>
                  <div className="rounded-md border border-emerald-200 bg-emerald-50/50 p-3">
                    <p className="text-xs text-muted-foreground">
                      {t("investor_plan.revenue_sharing.owner_block", { pct: ownerPct })}
                    </p>
                    <p className="font-bold tabular-nums mt-1 text-emerald-900">
                      {fmtInvestorXof(projection.years[0].ownerShare)}
                    </p>
                    <p className="text-xs text-emerald-800/80 mt-1">
                      {ownerPct} % × {fmtInvestorXof(projection.years[0].tibusRevenue, "")}
                    </p>
                  </div>
                </div>
              </div>
            ) : null}

            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
              <StatTile
                label={t("investor_plan.revenue_sharing.investment")}
                value={fmtInvestorXof(revenueSharing.investment)}
              />
              <StatTile
                label={t("investor_plan.revenue_sharing.cumul_investor")}
                value={fmtInvestorXof(revenueSharing.totalRevenueShare)}
              />
              <StatTile
                label={t("investor_plan.revenue_sharing.cumul_owner")}
                value={fmtInvestorXof(revenueSharing.totalOwnerShare)}
              />
              <StatTile
                label={t("investor_plan.revenue_sharing.total_roi")}
                value={fmtInvestorMultiple(revenueSharing.totalRoi)}
              />
            </div>
            <PlanTable
              headers={[
                t("investor_plan.revenue_sharing.col.period"),
                t("investor_plan.revenue_sharing.col.platform_revenue"),
                t("investor_plan.revenue_sharing.col.investor_rate"),
                t("investor_plan.revenue_sharing.col.investor_payout"),
                t("investor_plan.revenue_sharing.col.owner_rate"),
                t("investor_plan.revenue_sharing.col.owner_payout"),
                t("investor_plan.revenue_sharing.col.cumulative"),
                t("investor_plan.revenue_sharing.col.recovery"),
              ]}
              rows={[
                [
                  t("investor_plan.revenue_sharing.row_investment"),
                  "—",
                  "—",
                  fmtInvestorXof(-(revenueSharing.investment ?? 0)),
                  "—",
                  "—",
                  fmtInvestorXof(-(revenueSharing.investment ?? 0)),
                  "0 %",
                ],
                ...revenueSharing.years.map((row) => [
                  row.label,
                  fmtInvestorXof(row.platformRevenue),
                  `${row.investorShareRate} %`,
                  fmtInvestorXof(row.annualPayout),
                  `${row.ownerShareRate} %`,
                  fmtInvestorXof(row.ownerPayout),
                  fmtInvestorXof(row.cumulativeNet),
                  row.recoveryPct != null ? `${row.recoveryPct.toFixed(1)} %` : "—",
                ]),
              ]}
            />
            <p className="text-xs text-muted-foreground">
              {t("investor_plan.revenue_sharing.footer", {
                investor: inputs.investorEquityPct,
                owner: ownerPct,
                takeRate: inputs.tibusTakeRatePct,
                horizon: inputs.horizonYears,
                roi: fmtInvestorMultiple(revenueSharing.totalRoi),
              })}
            </p>
          </div>
        </CardContent>
      </Card>

      <Collapsible defaultOpen>
        <SectionShell title={t("investor_plan.sections.capital")}>
          <p className="text-xs text-muted-foreground mb-3">{INVESTOR_CAPITAL.financingNote}</p>
          <PlanTable headers={INVESTOR_CAPITAL_TABLE.headers} rows={INVESTOR_CAPITAL_TABLE.rows} />
        </SectionShell>
      </Collapsible>

      <Collapsible defaultOpen>
        <SectionShell title={t("investor_plan.sections.roi")}>
          <PlanTable headers={scenarios.headers} rows={scenarios.rows} />
        </SectionShell>
      </Collapsible>

      <Collapsible>
        <SectionShell title={t("investor_plan.sections.market")}>
          <PlanTable headers={INVESTOR_PLAN_MARKET.headers} rows={INVESTOR_PLAN_MARKET.rows} />
        </SectionShell>
      </Collapsible>

      <Collapsible>
        <SectionShell title={t("investor_plan.sections.model")}>
          <PlanTable headers={INVESTOR_PLAN_REVENUE_MODEL.headers} rows={INVESTOR_PLAN_REVENUE_MODEL.rows} />
        </SectionShell>
      </Collapsible>

      <Collapsible>
        <SectionShell title={t("investor_plan.sections.funding")}>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-4">
            <StatTile label={t("investor_plan.stats.levee")} value={fmtInvestorXof(INVESTOR_PLAN_LEVEE.amountXof)} />
            <StatTile label={t("investor_plan.stats.eur")} value={`~${leveeEur.toLocaleString("fr-FR")} kEUR`} />
            <StatTile label="Runway" value={INVESTOR_PLAN_LEVEE.runway} />
          </div>
          <PlanTable
            headers={["Poste", "Allocation"]}
            rows={INVESTOR_PLAN_LEVEE.usage.map((row) => [row.label, `${row.share} %`])}
          />
        </SectionShell>
      </Collapsible>

      <Collapsible>
        <SectionShell title={t("investor_plan.sections.roadmap")}>
          <PlanTable headers={INVESTOR_PLAN_ROADMAP.headers} rows={INVESTOR_PLAN_ROADMAP.rows} />
        </SectionShell>
      </Collapsible>

      <Collapsible>
        <SectionShell title={t("investor_plan.sections.advantages")}>
          <PlanTable headers={INVESTOR_PLAN_ADVANTAGES.headers} rows={INVESTOR_PLAN_ADVANTAGES.rows} />
        </SectionShell>
      </Collapsible>

      <Collapsible>
        <SectionShell title={t("investor_plan.sections.risks")}>
          <PlanTable headers={INVESTOR_PLAN_RISKS.headers} rows={INVESTOR_PLAN_RISKS.rows} />
        </SectionShell>
      </Collapsible>

      <p className="text-xs text-muted-foreground italic hidden print:block">
        {t("investor_plan.footer")}
      </p>
    </div>
  );
}

function SectionShell({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card className="print:shadow-none print:border">
      <CollapsibleTrigger asChild>
        <button type="button" className="w-full text-left">
          <CardHeader className="cursor-pointer hover:bg-muted/30 transition-colors">
            <CardTitle className="text-base">{title}</CardTitle>
          </CardHeader>
        </button>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <CardContent>{children}</CardContent>
      </CollapsibleContent>
    </Card>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  readOnly,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  readOnly?: boolean;
}) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs">{label}</Label>
      <Input
        value={value}
        placeholder={placeholder}
        readOnly={readOnly}
        className={readOnly ? "bg-muted/50" : undefined}
        onChange={(event) => onChange(event.target.value)}
      />
    </div>
  );
}

function StatTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="text-base font-bold tabular-nums mt-1">{value}</p>
    </div>
  );
}

function LoadingPlaceholder() {
  return (
    <Card>
      <CardContent className="pt-6 space-y-3">
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-32 w-full" />
      </CardContent>
    </Card>
  );
}

export { LoadingPlaceholder as InvestorPlanPanelSkeleton };
