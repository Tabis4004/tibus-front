import { useCallback, useEffect, useMemo, useState } from "react";
import { format, parseISO } from "date-fns";
import { useTranslation } from "react-i18next";
import { CreditCardIcon, RefreshCwIcon, SettingsIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog.tsx";
import { cn } from "@/lib/utils.ts";
import {
  assignCompanySubscriptionSupabase,
  listAdminCompanySubscriptionsSupabase,
  listAdminSubscriptionPlansSupabase,
  type AdminCompanySubscriptionRow,
  type AdminSubscriptionPlan,
} from "@/lib/supabase/admin-subscriptions.ts";

type CompanyOption = {
  id: string;
  name: string;
  countryId: string | null;
  countryName: string | null;
};

function fmtDate(iso: string | null) {
  if (!iso) return "—";
  try {
    return format(parseISO(iso), "dd/MM/yyyy");
  } catch {
    return iso;
  }
}

export default function SupabaseSubscriptionsTab({
  companies,
  onDataChanged,
}: {
  companies: CompanyOption[];
  onDataChanged?: () => void;
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [rows, setRows] = useState<AdminCompanySubscriptionRow[] | undefined>(undefined);
  const [plans, setPlans] = useState<AdminSubscriptionPlan[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const [manageCompany, setManageCompany] = useState<AdminCompanySubscriptionRow | null>(null);
  const [durationId, setDurationId] = useState("");
  const [saving, setSaving] = useState(false);

  const companyCountryById = useMemo(() => {
    const map = new Map<string, string | null>();
    for (const company of companies) map.set(company.id, company.countryId);
    return map;
  }, [companies]);

  const load = useCallback(async (silent = false) => {
    if (!silent) setRows(undefined);
    else setRefreshing(true);
    setError(null);
    try {
      const [subscriptionRows, planRows] = await Promise.all([
        listAdminCompanySubscriptionsSupabase(),
        listAdminSubscriptionPlansSupabase(),
      ]);
      setRows(subscriptionRows);
      setPlans(planRows);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur chargement");
      setRows([]);
    } finally {
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const durationOptions = useMemo(() => {
    if (!manageCompany) return [];
    const countryId = companyCountryById.get(manageCompany.companyId);
    if (!countryId) return [];

    const options: { id: string; label: string }[] = [];
    for (const plan of plans) {
      if (plan.countryId !== countryId) continue;
      for (const duration of plan.durations) {
        const priceLabel =
          duration.price === 0
            ? t("plans.free")
            : `${duration.price.toLocaleString()} ${plan.currency ?? ""}`;
        options.push({
          id: duration.id,
          label: `${plan.name} — ${duration.duration} ${t("plans.days")} — ${priceLabel}`,
        });
      }
    }
    return options;
  }, [companyCountryById, manageCompany, plans, t]);

  useEffect(() => {
    if (!manageCompany) {
      setDurationId("");
      return;
    }
    setDurationId(durationOptions[0]?.id ?? "");
  }, [manageCompany, durationOptions]);

  const handleAssign = async () => {
    if (!manageCompany || !durationId) return;
    setSaving(true);
    try {
      await assignCompanySubscriptionSupabase({
        companyId: manageCompany.companyId,
        durationId,
      });
      toast.success(t("sub_updated"));
      setManageCompany(null);
      await load(true);
      onDataChanged?.();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("sub_update_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between gap-3">
            <CardTitle className="text-base flex items-center gap-2">
              <CreditCardIcon className="w-4 h-4" />
              {t("company_subs")}
            </CardTitle>
            <Button
              size="sm"
              variant="outline"
              onClick={() => void load(true)}
              disabled={refreshing || rows === undefined}
              className="cursor-pointer"
            >
              <RefreshCwIcon className={cn("w-4 h-4", refreshing && "animate-spin")} />
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {rows === undefined ? (
            <div className="space-y-2">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
            </div>
          ) : error ? (
            <p className="text-sm text-destructive">{error}</p>
          ) : rows.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("no_subs_desc", { defaultValue: "Aucune entreprise trouvée." })}
            </p>
          ) : (
            <div className="divide-y">
              {rows.map((row) => (
                <div key={row.companyId} className="py-3 flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-medium truncate">{row.companyName}</p>
                    <p className="text-xs text-muted-foreground truncate">
                      {row.countryName ?? "—"}
                      {row.planName ? ` · ${row.planName}` : ` · ${t("plan_none")}`}
                      {row.duration ? ` · ${row.duration} ${t("plans.days")}` : ""}
                      {row.price !== null ? ` · ${row.price.toLocaleString()}` : ""}
                      {row.endDate ? ` · ${t("sub_until", { defaultValue: "jusqu'au" })} ${fmtDate(row.endDate)}` : ""}
                    </p>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <Badge variant={row.isActive ? "default" : "secondary"}>
                      {row.isActive ? t("status_active") : t("plans.inactive")}
                    </Badge>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="h-7 text-xs cursor-pointer"
                      onClick={() => setManageCompany(row)}
                    >
                      <SettingsIcon className="w-3 h-3 mr-1" />
                      {t("manage_sub")}
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={manageCompany !== null} onOpenChange={(open) => !open && setManageCompany(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("manage_sub_title")}</DialogTitle>
            <DialogDescription>
              {manageCompany?.companyName} — {t("manage_sub_desc")}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            {durationOptions.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {t("no_plans_for_country", {
                  defaultValue: "Aucun plan disponible pour le pays de cette entreprise. Créez-en un dans l'onglet Plans.",
                })}
              </p>
            ) : (
              <div className="space-y-1.5">
                <Label>{t("select_plan")}</Label>
                <Select value={durationId} onValueChange={setDurationId}>
                  <SelectTrigger>
                    <SelectValue placeholder={t("select_plan")} />
                  </SelectTrigger>
                  <SelectContent>
                    {durationOptions.map((option) => (
                      <SelectItem key={option.id} value={option.id}>
                        {option.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setManageCompany(null)} className="cursor-pointer">
              {tc("buttons.cancel")}
            </Button>
            <Button
              onClick={() => void handleAssign()}
              disabled={saving || !durationId}
              className="cursor-pointer"
            >
              {saving ? tc("buttons.saving") : tc("buttons.save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
