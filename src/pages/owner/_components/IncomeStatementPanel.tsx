import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, useParams } from "react-router-dom";
import { toast } from "sonner";
import { FileSpreadsheetIcon, RefreshCwIcon } from "lucide-react";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getCompanyIncomeStatementSupabase,
  type CompanyIncomeStatement,
} from "@/lib/supabase/income-statement.ts";

function fmt(amount: number, currency: string) {
  return `${amount.toLocaleString()} ${currency}`;
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function yearStartIso() {
  const now = new Date();
  return `${now.getFullYear()}-01-01`;
}

function amountClass(amount: number) {
  if (amount > 0) return "text-emerald-700 dark:text-emerald-400 font-semibold";
  if (amount < 0) return "text-red-700 dark:text-red-400 font-semibold";
  return "font-medium";
}

export default function IncomeStatementPanel({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const locale = lng ?? "fr";
  const [statement, setStatement] = useState<CompanyIncomeStatement | undefined>();
  const [refreshing, setRefreshing] = useState(false);
  const [periodFrom, setPeriodFrom] = useState(yearStartIso);
  const [periodTo, setPeriodTo] = useState(todayIso);

  const load = useCallback(
    async (silent = false) => {
      if (!silent) setStatement(undefined);
      else setRefreshing(true);
      try {
        setStatement(
          await getCompanyIncomeStatementSupabase(companyId, periodFrom, periodTo),
        );
      } catch (err) {
        toast.error(err instanceof Error ? err.message : t("income_statement.load_error"));
        setStatement(undefined);
      } finally {
        setRefreshing(false);
      }
    },
    [companyId, periodFrom, periodTo, t],
  );

  useEffect(() => {
    void load();
  }, [load]);

  if (!statement) {
    return <Skeleton className="h-96 w-full rounded-xl" />;
  }

  const { currency } = statement.company;

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-3">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                <FileSpreadsheetIcon className="w-4 h-4" />
                {t("income_statement.title")}
              </CardTitle>
              <p className="text-sm text-muted-foreground mt-1">
                {t("income_statement.framework", { framework: statement.framework })}
              </p>
            </div>
            <div className="flex flex-wrap items-end gap-2">
              <div>
                <Label className="text-xs">{t("income_statement.from")}</Label>
                <Input
                  type="date"
                  className="h-8 w-36"
                  value={periodFrom}
                  onChange={(e) => setPeriodFrom(e.target.value)}
                />
              </div>
              <div>
                <Label className="text-xs">{t("income_statement.to")}</Label>
                <Input
                  type="date"
                  className="h-8 w-36"
                  value={periodTo}
                  onChange={(e) => setPeriodTo(e.target.value)}
                />
              </div>
              <Button size="sm" variant="outline" disabled={refreshing} onClick={() => void load(true)}>
                <RefreshCwIcon className="w-4 h-4" />
              </Button>
              <Button size="sm" variant="outline" asChild>
                <Link to={`/${locale}/owner/expenses`}>{t("income_statement.manage_expenses")}</Link>
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="text-sm text-muted-foreground">
            {t("income_statement.period", {
              from: statement.period.from,
              to: statement.period.to,
            })}
          </div>

          <section>
            <h3 className="font-semibold text-[#1A5296] mb-2">
              {t("income_statement.products_title")}
            </h3>
            <table className="w-full text-sm">
              <tbody>
                {statement.products.lines.map((line) => (
                  <tr key={line.accountCode} className="border-b">
                    <td className="py-2 pr-3 text-muted-foreground w-20">{line.accountCode}</td>
                    <td className="py-2 pr-3">{line.accountLabel}</td>
                    <td className="py-2 text-right">{fmt(line.amount, currency)}</td>
                  </tr>
                ))}
                <tr className="font-semibold">
                  <td colSpan={2} className="py-2">{t("income_statement.total_products")}</td>
                  <td className="py-2 text-right">{fmt(statement.products.total, currency)}</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section>
            <h3 className="font-semibold text-[#1A5296] mb-2">
              {t("income_statement.charges_title")}
            </h3>
            {statement.charges.lines.length === 0 ? (
              <p className="text-sm text-muted-foreground">{t("income_statement.no_charges")}</p>
            ) : (
              <table className="w-full text-sm">
                <tbody>
                  {statement.charges.lines.map((line) => (
                    <tr key={`${line.accountCode}-${line.accountLabel}`} className="border-b">
                      <td className="py-2 pr-3 text-muted-foreground w-20">{line.accountCode}</td>
                      <td className="py-2 pr-3">{line.accountLabel}</td>
                      <td className="py-2 text-right">{fmt(line.amount, currency)}</td>
                    </tr>
                  ))}
                  <tr className="font-semibold">
                    <td colSpan={2} className="py-2">{t("income_statement.total_charges")}</td>
                    <td className="py-2 text-right">{fmt(statement.charges.total, currency)}</td>
                  </tr>
                </tbody>
              </table>
            )}
          </section>

          <section className="rounded-lg border bg-muted/30 p-4 space-y-2">
            <div className="flex justify-between text-sm">
              <span>{t("income_statement.operating_result")}</span>
              <span className={amountClass(statement.results.operatingResult)}>
                {fmt(statement.results.operatingResult, currency)}
              </span>
            </div>
            <div className="flex justify-between text-sm">
              <span>{t("income_statement.financial_result")}</span>
              <span>{fmt(statement.results.financialResult, currency)}</span>
            </div>
            <div className="flex justify-between font-bold text-base border-t pt-2">
              <span>{t("income_statement.net_result")}</span>
              <span className={amountClass(statement.results.netResult)}>
                {fmt(statement.results.netResult, currency)}
              </span>
            </div>
          </section>
        </CardContent>
      </Card>
    </div>
  );
}
