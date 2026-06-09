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
import {
  buildInvestorRoiScenarioRows,
  computeInvestorFinancials,
  computeInvestorRoi,
  DEFAULT_INVESTOR_ROI_INPUTS,
  fmtInvestorMultiple,
  fmtInvestorPercent,
  fmtInvestorXof,
  INVESTOR_PLAN_ADVANTAGES,
  INVESTOR_PLAN_LEVEE,
  INVESTOR_PLAN_MARKET,
  INVESTOR_PLAN_META,
  INVESTOR_PLAN_REVENUE_MODEL,
  INVESTOR_PLAN_RISKS,
  INVESTOR_PLAN_ROADMAP,
  type InvestorRoiInputs,
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
              <th key={header} className="px-3 py-2 font-medium">
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={index} className="border-b last:border-0">
              {row.map((cell, cellIndex) => (
                <td key={cellIndex} className="px-3 py-2 align-top">
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

export default function InvestorPlanPanel() {
  const { t } = useTranslation("admin");
  const printRef = useRef<HTMLDivElement>(null);
  const [inputs, setInputs] = useState<InvestorRoiInputs>(DEFAULT_INVESTOR_ROI_INPUTS);
  const [loadingLive, setLoadingLive] = useState(true);

  const financials = useMemo(() => computeInvestorFinancials(), []);
  const base = financials[3];
  const roi = useMemo(() => computeInvestorRoi(inputs), [inputs]);
  const scenarios = useMemo(() => buildInvestorRoiScenarioRows(), []);
  const roiReady = roi.roi != null;

  const applyLiveMetrics = useCallback(() => {
    setLoadingLive(true);
    void getPlatformScalingMetricsSupabase()
      .then((metrics) => {
        setInputs((current) => ({
          ...current,
          companies: metrics.companiesActive || current.companies,
          ticketsMonth: Math.max(
            1,
            Math.round(metrics.avgTicketsPerDay30d * 30) || current.ticketsMonth,
          ),
        }));
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
              levee: fmtInvestorXof(INVESTOR_PLAN_LEVEE.amountXof),
              gmv: fmtInvestorXof(base.gmvYear),
              revenue: fmtInvestorXof(base.revTotal),
              roi: fmtInvestorMultiple(base.revTotal / INVESTOR_PLAN_LEVEE.amountXof),
            })}
          </div>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <StatTile label={t("investor_plan.stats.levee")} value={fmtInvestorXof(INVESTOR_PLAN_LEVEE.amountXof)} />
            <StatTile label={t("investor_plan.stats.gmv")} value={fmtInvestorXof(base.gmvYear)} />
            <StatTile label={t("investor_plan.stats.revenue")} value={fmtInvestorXof(base.revTotal)} />
            <StatTile
              label={t("investor_plan.stats.roi_base")}
              value={`${fmtInvestorMultiple(base.revTotal / INVESTOR_PLAN_LEVEE.amountXof)} · TRI ~38 %`}
            />
          </div>
        </CardContent>
      </Card>

      <Card className="print:shadow-none print:border">
        <CardHeader>
          <CardTitle className="text-base">{t("investor_plan.simulator_title")}</CardTitle>
          <p className="text-xs text-muted-foreground">{t("investor_plan.simulator_desc")}</p>
        </CardHeader>
        <CardContent className="space-y-4">
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
            <StatTile label={t("investor_plan.stats.revenue")} value={fmtInvestorXof(roi.revTotal)} />
            <StatTile label="GMV" value={fmtInvestorXof(roi.gmvYear)} />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 print:hidden">
            <div className="grid grid-cols-2 gap-3">
              <Field label={t("investor_plan.fields.companies")} value={String(inputs.companies)} onChange={(v) => updateField("companies", v)} />
              <Field label={t("investor_plan.fields.tickets")} value={String(inputs.ticketsMonth)} onChange={(v) => updateField("ticketsMonth", v)} />
              <Field label={t("investor_plan.fields.ticket_avg")} value={String(inputs.avgTicket)} onChange={(v) => updateField("avgTicket", v)} />
              <Field label={t("investor_plan.fields.take_rate")} value={String(inputs.takeRatePct)} onChange={(v) => updateField("takeRatePct", v)} />
              <Field label={t("investor_plan.fields.abo")} value={String(inputs.aboMonth)} onChange={(v) => updateField("aboMonth", v)} />
              <Field
                label={t("investor_plan.fields.investment")}
                value={inputs.investmentXof == null ? "" : String(inputs.investmentXof)}
                onChange={(v) => updateField("investmentXof", v)}
                placeholder="250000000"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Field label={t("investor_plan.fields.equity")} value={String(inputs.equityPct)} onChange={(v) => updateField("equityPct", v)} />
              <Field label={t("investor_plan.fields.exit_multiple")} value={String(inputs.exitMultiple)} onChange={(v) => updateField("exitMultiple", v)} />
              <Field label={t("investor_plan.fields.horizon")} value={String(inputs.horizonYears)} onChange={(v) => updateField("horizonYears", v)} />
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
        </CardContent>
      </Card>

      <Collapsible defaultOpen>
        <SectionShell title={t("investor_plan.sections.financials")}>
          <PlanTable
            headers={["Année", "Compagnies", "Billets/mois", "GMV annuel", "Rev. commission", "Rev. abo", "Rev. total", "EBITDA"]}
            rows={financials.map((row) => [
              row.year,
              String(row.companies),
              fmtInvestorXof(row.ticketsMonth, ""),
              fmtInvestorXof(row.gmvYear),
              fmtInvestorXof(row.revCommission),
              fmtInvestorXof(row.revAbo),
              fmtInvestorXof(row.revTotal),
              fmtInvestorXof(row.ebitda),
            ])}
          />
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
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs">{label}</Label>
      <Input value={value} placeholder={placeholder} onChange={(event) => onChange(event.target.value)} />
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
