import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import {
  BusIcon,
  PencilIcon,
  PlusIcon,
  RefreshCwIcon,
  Trash2Icon,
  UserIcon,
} from "lucide-react";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  deleteCompanyExpenseCategorySupabase,
  deleteCompanyExpenseSupabase,
  listCompanyExpenseCategoriesSupabase,
  listCompanyExpensesSupabase,
  upsertCompanyExpenseCategorySupabase,
  upsertCompanyExpenseSupabase,
  type CompanyExpense,
  type CompanyExpenseCategory,
} from "@/lib/supabase/expenses.ts";
import {
  listOwnerFleetBusesSupabase,
  listOwnerStationsSupabase,
  listOwnerTeamSupabase,
  type SupabaseOwnerBus,
  type SupabaseOwnerStation,
  type SupabaseOwnerTeamMember,
} from "@/lib/supabase/owner-operations.ts";

type ImputationMode = "team" | "bus";

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

export default function ExpensesPanel({ companyId }: { companyId: string }) {
  const { t } = useTranslation("owner");
  const appUser = useAppUser();
  const { appUserId } = useSupabaseAuth();
  const [categories, setCategories] = useState<CompanyExpenseCategory[] | undefined>();
  const [expenses, setExpenses] = useState<CompanyExpense[] | undefined>();
  const [team, setTeam] = useState<SupabaseOwnerTeamMember[]>([]);
  const [buses, setBuses] = useState<SupabaseOwnerBus[]>([]);
  const [stations, setStations] = useState<SupabaseOwnerStation[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [periodFrom, setPeriodFrom] = useState(yearStartIso);
  const [periodTo, setPeriodTo] = useState(todayIso());

  const [expenseDialogOpen, setExpenseDialogOpen] = useState(false);
  const [categoryDialogOpen, setCategoryDialogOpen] = useState(false);
  const [editingExpense, setEditingExpense] = useState<CompanyExpense | null>(null);
  const [editingCategory, setEditingCategory] = useState<CompanyExpenseCategory | null>(null);
  const [saving, setSaving] = useState(false);

  const [expenseForm, setExpenseForm] = useState({
    categoryId: "",
    amount: "",
    expenseDate: todayIso(),
    description: "",
    imputationMode: "team" as ImputationMode,
    teamMemberUserId: "",
    busId: "",
    gareId: "",
  });

  const [categoryForm, setCategoryForm] = useState({
    name: "",
    ohadaAccountCode: "622",
    ohadaAccountLabel: "Services extérieurs",
  });

  const canEdit =
    appUser.roles.includes("owner") || appUser.roles.includes("comptable_compagnie");

  const totalExpenses = useMemo(
    () => (expenses ?? []).reduce((sum, row) => sum + row.amount, 0),
    [expenses],
  );

  const currency = expenses?.[0]?.currency ?? "XOF";

  const load = useCallback(
    async (silent = false) => {
      if (!silent) {
        setCategories(undefined);
        setExpenses(undefined);
      } else {
        setRefreshing(true);
      }
      try {
        const [cats, rows] = await Promise.all([
          listCompanyExpenseCategoriesSupabase(companyId),
          listCompanyExpensesSupabase(companyId, periodFrom, periodTo),
        ]);
        setCategories(cats);
        setExpenses(rows);
      } catch (err) {
        toast.error(err instanceof Error ? err.message : t("expenses.load_error"));
        setCategories([]);
        setExpenses([]);
      } finally {
        setRefreshing(false);
      }
    },
    [companyId, periodFrom, periodTo, t],
  );

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (!appUserId) return;
    void listOwnerTeamSupabase(appUserId, companyId).then(setTeam).catch(() => setTeam([]));
    void listOwnerFleetBusesSupabase(appUserId, companyId).then(setBuses).catch(() => setBuses([]));
    void listOwnerStationsSupabase(appUserId, companyId).then(setStations).catch(() => setStations([]));
  }, [appUserId, companyId]);

  const openNewExpense = () => {
    setEditingExpense(null);
    setExpenseForm({
      categoryId: categories?.[0]?.id ?? "",
      amount: "",
      expenseDate: todayIso(),
      description: "",
      imputationMode: "team",
      teamMemberUserId: team[0]?.id ?? "",
      busId: buses[0]?.id ?? "",
      gareId: stations[0]?.id ?? "",
    });
    setExpenseDialogOpen(true);
  };

  const openEditExpense = (row: CompanyExpense) => {
    setEditingExpense(row);
    const isTeam = Boolean(row.teamMemberUserId);
    setExpenseForm({
      categoryId: row.categoryId,
      amount: String(row.amount),
      expenseDate: row.expenseDate,
      description: row.description ?? "",
      imputationMode: isTeam ? "team" : "bus",
      teamMemberUserId: row.teamMemberUserId ?? "",
      busId: row.busId ?? "",
      gareId: row.gareId ?? "",
    });
    setExpenseDialogOpen(true);
  };

  const openNewCategory = () => {
    setEditingCategory(null);
    setCategoryForm({
      name: "",
      ohadaAccountCode: "622",
      ohadaAccountLabel: "Services extérieurs",
    });
    setCategoryDialogOpen(true);
  };

  const openEditCategory = (row: CompanyExpenseCategory) => {
    setEditingCategory(row);
    setCategoryForm({
      name: row.name,
      ohadaAccountCode: row.ohadaAccountCode,
      ohadaAccountLabel: row.ohadaAccountLabel,
    });
    setCategoryDialogOpen(true);
  };

  const saveExpense = async () => {
    const amount = Number(expenseForm.amount);
    if (!expenseForm.categoryId || !Number.isFinite(amount) || amount <= 0) {
      toast.error(t("expenses.validation_amount"));
      return;
    }
    if (expenseForm.imputationMode === "team" && !expenseForm.teamMemberUserId) {
      toast.error(t("expenses.validation_team"));
      return;
    }
    if (expenseForm.imputationMode === "bus" && (!expenseForm.busId || !expenseForm.gareId)) {
      toast.error(t("expenses.validation_bus_gare"));
      return;
    }

    setSaving(true);
    try {
      await upsertCompanyExpenseSupabase({
        companyId,
        id: editingExpense?.id,
        categoryId: expenseForm.categoryId,
        amount,
        expenseDate: expenseForm.expenseDate,
        description: expenseForm.description || null,
        teamMemberUserId:
          expenseForm.imputationMode === "team" ? expenseForm.teamMemberUserId : null,
        busId: expenseForm.imputationMode === "bus" ? expenseForm.busId : null,
        gareId: expenseForm.imputationMode === "bus" ? expenseForm.gareId : null,
      });
      toast.success(editingExpense ? t("expenses.updated") : t("expenses.created"));
      setExpenseDialogOpen(false);
      await load(true);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("expenses.save_error"));
    } finally {
      setSaving(false);
    }
  };

  const saveCategory = async () => {
    if (!categoryForm.name.trim()) {
      toast.error(t("expenses.validation_category"));
      return;
    }
    setSaving(true);
    try {
      await upsertCompanyExpenseCategorySupabase({
        companyId,
        id: editingCategory?.id,
        name: categoryForm.name.trim(),
        ohadaAccountCode: categoryForm.ohadaAccountCode.trim(),
        ohadaAccountLabel: categoryForm.ohadaAccountLabel.trim(),
      });
      toast.success(editingCategory ? t("expenses.category_updated") : t("expenses.category_created"));
      setCategoryDialogOpen(false);
      await load(true);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("expenses.category_save_error"));
    } finally {
      setSaving(false);
    }
  };

  const removeExpense = async (row: CompanyExpense) => {
    if (!window.confirm(t("expenses.delete_confirm"))) return;
    try {
      await deleteCompanyExpenseSupabase(companyId, row.id);
      toast.success(t("expenses.deleted"));
      await load(true);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("expenses.delete_error"));
    }
  };

  const removeCategory = async (row: CompanyExpenseCategory) => {
    if (!window.confirm(t("expenses.category_delete_confirm"))) return;
    try {
      await deleteCompanyExpenseCategorySupabase(companyId, row.id);
      toast.success(t("expenses.category_deleted"));
      await load(true);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("expenses.category_delete_error"));
    }
  };

  if (!categories || !expenses) {
    return <Skeleton className="h-72 w-full rounded-xl" />;
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <CardTitle className="text-base">{t("expenses.categories_title")}</CardTitle>
            {canEdit ? (
              <Button size="sm" onClick={openNewCategory}>
                <PlusIcon className="w-4 h-4 mr-1.5" />
                {t("expenses.add_category")}
              </Button>
            ) : null}
          </div>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            {categories.map((cat) => (
              <Badge key={cat.id} variant="secondary" className="gap-1 py-1.5 px-2.5">
                <span>{cat.name}</span>
                <span className="text-muted-foreground text-xs">({cat.ohadaAccountCode})</span>
                {canEdit ? (
                  <>
                    <button
                      type="button"
                      className="ml-1 opacity-70 hover:opacity-100"
                      onClick={() => openEditCategory(cat)}
                      aria-label={t("expenses.edit_category")}
                    >
                      <PencilIcon className="w-3 h-3" />
                    </button>
                    <button
                      type="button"
                      className="opacity-70 hover:opacity-100"
                      onClick={() => void removeCategory(cat)}
                      aria-label={t("expenses.delete_category")}
                    >
                      <Trash2Icon className="w-3 h-3" />
                    </button>
                  </>
                ) : null}
              </Badge>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <CardTitle className="text-base">{t("expenses.list_title")}</CardTitle>
              <p className="text-sm text-muted-foreground mt-1">
                {t("expenses.total_period", { amount: fmt(totalExpenses, currency) })}
              </p>
            </div>
            <div className="flex flex-wrap items-end gap-2">
              <div>
                <Label className="text-xs">{t("expenses.from")}</Label>
                <Input
                  type="date"
                  className="h-8 w-36"
                  value={periodFrom}
                  onChange={(e) => setPeriodFrom(e.target.value)}
                />
              </div>
              <div>
                <Label className="text-xs">{t("expenses.to")}</Label>
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
              {canEdit ? (
                <Button size="sm" onClick={openNewExpense}>
                  <PlusIcon className="w-4 h-4 mr-1.5" />
                  {t("expenses.add")}
                </Button>
              ) : null}
            </div>
          </div>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {expenses.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("expenses.empty")}</p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left text-muted-foreground">
                  <th className="py-2 pr-3">{t("expenses.col_date")}</th>
                  <th className="py-2 pr-3">{t("expenses.col_category")}</th>
                  <th className="py-2 pr-3">{t("expenses.col_amount")}</th>
                  <th className="py-2 pr-3">{t("expenses.col_imputation")}</th>
                  <th className="py-2 pr-3">{t("expenses.col_description")}</th>
                  {canEdit ? <th className="py-2" /> : null}
                </tr>
              </thead>
              <tbody>
                {expenses.map((row) => (
                  <tr key={row.id} className="border-b last:border-0">
                    <td className="py-2 pr-3 whitespace-nowrap">{row.expenseDate}</td>
                    <td className="py-2 pr-3">
                      <div>{row.categoryName}</div>
                      <div className="text-xs text-muted-foreground">{row.ohadaAccountCode}</div>
                    </td>
                    <td className="py-2 pr-3 font-medium">{fmt(row.amount, row.currency)}</td>
                    <td className="py-2 pr-3">
                      {row.teamMemberUserId ? (
                        <span className="inline-flex items-center gap-1">
                          <UserIcon className="w-3.5 h-3.5" />
                          {row.teamMemberName || t("expenses.team_member")}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1">
                          <BusIcon className="w-3.5 h-3.5" />
                          {row.busLabel} — {row.gareName}
                        </span>
                      )}
                    </td>
                    <td className="py-2 pr-3 text-muted-foreground">{row.description || "—"}</td>
                    {canEdit ? (
                      <td className="py-2 whitespace-nowrap">
                        <Button size="sm" variant="ghost" onClick={() => openEditExpense(row)}>
                          <PencilIcon className="w-4 h-4" />
                        </Button>
                        <Button size="sm" variant="ghost" onClick={() => void removeExpense(row)}>
                          <Trash2Icon className="w-4 h-4" />
                        </Button>
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      <Dialog open={expenseDialogOpen} onOpenChange={setExpenseDialogOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>
              {editingExpense ? t("expenses.edit_title") : t("expenses.new_title")}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>{t("expenses.field_category")}</Label>
              <Select
                value={expenseForm.categoryId}
                onValueChange={(v) => setExpenseForm((f) => ({ ...f, categoryId: v }))}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {categories.map((cat) => (
                    <SelectItem key={cat.id} value={cat.id}>{cat.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>{t("expenses.field_amount")}</Label>
                <Input
                  type="number"
                  min={1}
                  value={expenseForm.amount}
                  onChange={(e) => setExpenseForm((f) => ({ ...f, amount: e.target.value }))}
                />
              </div>
              <div>
                <Label>{t("expenses.field_date")}</Label>
                <Input
                  type="date"
                  value={expenseForm.expenseDate}
                  onChange={(e) => setExpenseForm((f) => ({ ...f, expenseDate: e.target.value }))}
                />
              </div>
            </div>
            <div>
              <Label>{t("expenses.field_imputation")}</Label>
              <Select
                value={expenseForm.imputationMode}
                onValueChange={(v) =>
                  setExpenseForm((f) => ({ ...f, imputationMode: v as ImputationMode }))
                }
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="team">{t("expenses.imputation_team")}</SelectItem>
                  <SelectItem value="bus">{t("expenses.imputation_bus")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {expenseForm.imputationMode === "team" ? (
              <div>
                <Label>{t("expenses.field_team_member")}</Label>
                <Select
                  value={expenseForm.teamMemberUserId}
                  onValueChange={(v) => setExpenseForm((f) => ({ ...f, teamMemberUserId: v }))}
                >
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {team.map((member) => (
                      <SelectItem key={member.id} value={member.id}>{member.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <Label>{t("expenses.field_bus")}</Label>
                  <Select
                    value={expenseForm.busId}
                    onValueChange={(v) => setExpenseForm((f) => ({ ...f, busId: v }))}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {buses.map((bus) => (
                        <SelectItem key={bus.id} value={bus.id}>
                          {bus.name} ({bus.plateNumber})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>{t("expenses.field_gare")}</Label>
                  <Select
                    value={expenseForm.gareId}
                    onValueChange={(v) => setExpenseForm((f) => ({ ...f, gareId: v }))}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {stations.map((station) => (
                        <SelectItem key={station.id} value={station.id}>{station.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>
            )}
            <div>
              <Label>{t("expenses.field_description")}</Label>
              <Textarea
                value={expenseForm.description}
                onChange={(e) => setExpenseForm((f) => ({ ...f, description: e.target.value }))}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setExpenseDialogOpen(false)}>
              {t("expenses.cancel")}
            </Button>
            <Button disabled={saving} onClick={() => void saveExpense()}>
              {t("expenses.save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={categoryDialogOpen} onOpenChange={setCategoryDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {editingCategory ? t("expenses.edit_category_title") : t("expenses.new_category_title")}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>{t("expenses.field_category_name")}</Label>
              <Input
                value={categoryForm.name}
                onChange={(e) => setCategoryForm((f) => ({ ...f, name: e.target.value }))}
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>{t("expenses.field_ohada_code")}</Label>
                <Input
                  value={categoryForm.ohadaAccountCode}
                  onChange={(e) => setCategoryForm((f) => ({ ...f, ohadaAccountCode: e.target.value }))}
                />
              </div>
              <div>
                <Label>{t("expenses.field_ohada_label")}</Label>
                <Input
                  value={categoryForm.ohadaAccountLabel}
                  onChange={(e) => setCategoryForm((f) => ({ ...f, ohadaAccountLabel: e.target.value }))}
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCategoryDialogOpen(false)}>
              {t("expenses.cancel")}
            </Button>
            <Button disabled={saving} onClick={() => void saveCategory()}>
              {t("expenses.save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
