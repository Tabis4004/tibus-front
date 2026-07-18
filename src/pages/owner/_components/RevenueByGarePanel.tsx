import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { BuildingIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getCompanyRevenueByGareSupabase,
  type CompanyGareRevenue,
} from "@/lib/supabase/accounting.ts";

/** Récap "montants par agence" demandé par le promoteur : le dashboard
 * global n'affiche qu'un montant unique pour toute la compagnie — ce
 * panneau ventile billets/colis/total/caisse ouverte gare par gare. */
export default function RevenueByGarePanel({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const [rows, setRows] = useState<CompanyGareRevenue[] | null | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    setRows(undefined);
    void (async () => {
      try {
        const data = await getCompanyRevenueByGareSupabase(companyId);
        if (!cancelled) setRows(data);
      } catch {
        if (!cancelled) setRows(null);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [companyId]);

  const currency = rows?.[0]?.currency ?? "XOF";
  const formatMoney = (amount: number) => `${amount.toLocaleString()} ${currency}`;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <BuildingIcon className="w-4 h-4" />
          {t("revenue_by_gare.title")}
        </CardTitle>
        <p className="text-xs text-muted-foreground">{t("revenue_by_gare.subtitle")}</p>
      </CardHeader>
      <CardContent>
        {rows === undefined ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-12 rounded-lg" />
            ))}
          </div>
        ) : rows === null ? (
          <p className="text-sm text-destructive">{t("revenue_by_gare.load_error")}</p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("revenue_by_gare.empty")}</p>
        ) : (
          <div className="overflow-x-auto -mx-2">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-muted-foreground uppercase tracking-wide">
                  <th className="px-2 py-2 font-medium">{t("revenue_by_gare.col_gare")}</th>
                  <th className="px-2 py-2 font-medium text-right">
                    {t("revenue_by_gare.col_tickets")}
                  </th>
                  <th className="px-2 py-2 font-medium text-right">
                    {t("revenue_by_gare.col_colis")}
                  </th>
                  <th className="px-2 py-2 font-medium text-right">
                    {t("revenue_by_gare.col_total")}
                  </th>
                  <th className="px-2 py-2 font-medium text-right">
                    {t("revenue_by_gare.col_caisse")}
                  </th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.gareId} className="border-t">
                    <td className="px-2 py-2.5 font-medium">{row.gareName}</td>
                    <td className="px-2 py-2.5 text-right tabular-nums">
                      {formatMoney(row.ticketRevenue)}
                    </td>
                    <td className="px-2 py-2.5 text-right tabular-nums">
                      {formatMoney(row.colisRevenue)}
                    </td>
                    <td className="px-2 py-2.5 text-right tabular-nums font-semibold">
                      {formatMoney(row.totalRevenue)}
                    </td>
                    <td className="px-2 py-2.5 text-right tabular-nums text-muted-foreground">
                      {formatMoney(row.openCaisseBalance)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
