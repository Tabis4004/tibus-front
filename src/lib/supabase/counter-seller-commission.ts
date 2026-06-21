import { supabase } from "@/lib/supabase";

export type CounterCommissionTier = {
  id: string;
  companyId: string;
  gareId: string | null;
  roleScope: "vendeur" | "vendeur_gare";
  minAmount: number;
  maxAmount: number | null;
  commissionType: "fixed" | "percentage";
  commissionValue: number;
  isActive: boolean;
  sortOrder: number;
};

function mapTier(row: Record<string, unknown>): CounterCommissionTier {
  return {
    id: String(row.id),
    companyId: String(row.companyId),
    gareId: row.gareId ? String(row.gareId) : null,
    roleScope: row.roleScope === "vendeur_gare" ? "vendeur_gare" : "vendeur",
    minAmount: Number(row.minAmount ?? 0),
    maxAmount: row.maxAmount != null ? Number(row.maxAmount) : null,
    commissionType: row.commissionType === "fixed" ? "fixed" : "percentage",
    commissionValue: Number(row.commissionValue ?? 0),
    isActive: Boolean(row.isActive),
    sortOrder: Number(row.sortOrder ?? 0),
  };
}

export async function listCounterCommissionTiersSupabase(
  companyId: string,
  gareId?: string | null,
): Promise<CounterCommissionTier[]> {
  const { data, error } = await supabase.rpc("list_gare_counter_commission_tiers", {
    p_company_id: companyId,
    p_gare_id: gareId ?? null,
  });
  if (error) throw error;
  return (data ?? []).map((row) => mapTier(row as Record<string, unknown>));
}

export async function upsertCounterCommissionTierSupabase(input: {
  id?: string | null;
  companyId: string;
  gareId?: string | null;
  roleScope: "vendeur" | "vendeur_gare";
  minAmount: number;
  maxAmount?: number | null;
  commissionType: "fixed" | "percentage";
  commissionValue: number;
  isActive?: boolean;
  sortOrder?: number;
}): Promise<string> {
  const { data, error } = await supabase.rpc("upsert_gare_counter_commission_tier", {
    p_id: input.id ?? null,
    p_company_id: input.companyId,
    p_gare_id: input.gareId ?? null,
    p_role_scope: input.roleScope,
    p_min_amount: input.minAmount,
    p_max_amount: input.maxAmount ?? null,
    p_commission_type: input.commissionType,
    p_commission_value: input.commissionValue,
    p_is_active: input.isActive ?? true,
    p_sort_order: input.sortOrder ?? 0,
  });
  if (error) throw error;
  return String(data);
}

export async function deleteCounterCommissionTierSupabase(id: string): Promise<void> {
  const { error } = await supabase.rpc("delete_gare_counter_commission_tier", { p_id: id });
  if (error) throw error;
}

export async function computeCounterSellerCommissionSupabase(input: {
  amount: number;
  companyId: string;
  gareId?: string | null;
  sellerUserId?: string | null;
}): Promise<number> {
  const { data, error } = await supabase.rpc("compute_counter_seller_commission", {
    p_amount: input.amount,
    p_company_id: input.companyId,
    p_gare_id: input.gareId ?? null,
    p_seller_user_id: input.sellerUserId ?? null,
  });
  if (error) throw error;
  return Number(data ?? 0);
}
