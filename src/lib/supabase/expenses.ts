import { supabase } from "@/lib/supabase";

export type CompanyExpenseCategory = {
  id: string;
  name: string;
  ohadaAccountCode: string;
  ohadaAccountLabel: string;
  sortOrder: number;
  isPreset: boolean;
};

export type CompanyExpense = {
  id: string;
  categoryId: string;
  categoryName: string;
  ohadaAccountCode: string;
  amount: number;
  currency: string;
  expenseDate: string;
  description: string | null;
  teamMemberUserId: string | null;
  teamMemberName: string | null;
  busId: string | null;
  busLabel: string | null;
  gareId: string | null;
  gareName: string | null;
  createdAt: string;
};

function mapCategory(row: Record<string, unknown>): CompanyExpenseCategory {
  return {
    id: row.id as string,
    name: row.name as string,
    ohadaAccountCode: row.ohadaAccountCode as string,
    ohadaAccountLabel: row.ohadaAccountLabel as string,
    sortOrder: Number(row.sortOrder ?? 0),
    isPreset: Boolean(row.isPreset),
  };
}

function mapExpense(row: Record<string, unknown>): CompanyExpense {
  return {
    id: row.id as string,
    categoryId: row.categoryId as string,
    categoryName: row.categoryName as string,
    ohadaAccountCode: row.ohadaAccountCode as string,
    amount: Number(row.amount ?? 0),
    currency: (row.currency as string) || "XOF",
    expenseDate: row.expenseDate as string,
    description: (row.description as string | null) ?? null,
    teamMemberUserId: (row.teamMemberUserId as string | null) ?? null,
    teamMemberName: (row.teamMemberName as string | null) ?? null,
    busId: (row.busId as string | null) ?? null,
    busLabel: (row.busLabel as string | null) ?? null,
    gareId: (row.gareId as string | null) ?? null,
    gareName: (row.gareName as string | null) ?? null,
    createdAt: row.createdAt as string,
  };
}

export async function listCompanyExpenseCategoriesSupabase(
  companyId: string,
): Promise<CompanyExpenseCategory[]> {
  const { data, error } = await supabase.rpc("list_company_expense_categories", {
    p_company_id: companyId,
  });
  if (error) throw error;
  return ((data as Record<string, unknown>[]) ?? []).map(mapCategory);
}

export async function upsertCompanyExpenseCategorySupabase(input: {
  companyId: string;
  id?: string | null;
  name: string;
  ohadaAccountCode?: string;
  ohadaAccountLabel?: string;
}): Promise<string> {
  const { data, error } = await supabase.rpc("upsert_company_expense_category", {
    p_company_id: input.companyId,
    p_id: input.id ?? null,
    p_name: input.name,
    p_ohada_account_code: input.ohadaAccountCode ?? "622",
    p_ohada_account_label: input.ohadaAccountLabel ?? "Services extérieurs",
  });
  if (error) throw error;
  return (data as { id: string }).id;
}

export async function deleteCompanyExpenseCategorySupabase(
  companyId: string,
  categoryId: string,
): Promise<void> {
  const { error } = await supabase.rpc("delete_company_expense_category", {
    p_company_id: companyId,
    p_id: categoryId,
  });
  if (error) throw error;
}

export async function listCompanyExpensesSupabase(
  companyId: string,
  from?: string | null,
  to?: string | null,
): Promise<CompanyExpense[]> {
  const { data, error } = await supabase.rpc("list_company_expenses", {
    p_company_id: companyId,
    p_from: from ?? null,
    p_to: to ?? null,
  });
  if (error) throw error;
  return ((data as Record<string, unknown>[]) ?? []).map(mapExpense);
}

export async function upsertCompanyExpenseSupabase(input: {
  companyId: string;
  id?: string | null;
  categoryId: string;
  amount: number;
  expenseDate: string;
  description?: string | null;
  teamMemberUserId?: string | null;
  busId?: string | null;
  gareId?: string | null;
}): Promise<string> {
  const { data, error } = await supabase.rpc("upsert_company_expense", {
    p_company_id: input.companyId,
    p_id: input.id ?? null,
    p_category_id: input.categoryId,
    p_amount: input.amount,
    p_expense_date: input.expenseDate,
    p_description: input.description ?? null,
    p_team_member_user_id: input.teamMemberUserId ?? null,
    p_bus_id: input.busId ?? null,
    p_gare_id: input.gareId ?? null,
  });
  if (error) throw error;
  return (data as { id: string }).id;
}

export async function deleteCompanyExpenseSupabase(
  companyId: string,
  expenseId: string,
): Promise<void> {
  const { error } = await supabase.rpc("delete_company_expense", {
    p_company_id: companyId,
    p_id: expenseId,
  });
  if (error) throw error;
}
