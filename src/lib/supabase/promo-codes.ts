import { supabase } from "@/lib/supabase";

export type OwnerPromoCode = {
  id: string;
  code: string;
  discountType: "percentage" | "fixed";
  discountValue: number;
  currency: string | null;
  validFrom: string;
  validUntil: string;
  maxUsage: number | null;
  usageCount: number;
  trajetId: string | null;
  isActive: boolean;
  routeLabel: string | null;
};

function mapPromoRow(row: Record<string, unknown>): OwnerPromoCode {
  const discountType = String(row.discountType ?? "percentage");
  return {
    id: String(row.id),
    code: String(row.code ?? ""),
    discountType: discountType === "fixed" ? "fixed" : "percentage",
    discountValue: Number(row.discountValue ?? 0),
    currency: row.currency ? String(row.currency) : null,
    validFrom: String(row.validFrom ?? ""),
    validUntil: String(row.validUntil ?? ""),
    maxUsage: row.maxUsage != null ? Number(row.maxUsage) : null,
    usageCount: Number(row.usageCount ?? 0),
    trajetId: row.trajetId ? String(row.trajetId) : null,
    isActive: Boolean(row.isActive),
    routeLabel: row.routeLabel ? String(row.routeLabel) : null,
  };
}

export async function listOwnerPromoCodesSupabase(): Promise<OwnerPromoCode[]> {
  const { data, error } = await supabase.rpc("list_owner_promo_codes");
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  return rows
    .filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === "object")
    .map(mapPromoRow);
}

export async function createOwnerPromoCodeSupabase(input: {
  code: string;
  discountType: "percentage" | "fixed";
  discountValue: number;
  validFrom: string;
  validUntil: string;
  currency?: string;
  maxUsage?: number;
  trajetId?: string;
}): Promise<string> {
  const { data, error } = await supabase.rpc("create_owner_promo_code", {
    p_code: input.code,
    p_discount_type: input.discountType,
    p_discount_value: input.discountValue,
    p_valid_from: input.validFrom,
    p_valid_until: input.validUntil,
    p_currency: input.currency ?? null,
    p_max_usage: input.maxUsage ?? null,
    p_trajet_id: input.trajetId ?? null,
  });
  if (error) throw error;
  return String(data ?? "");
}

export async function updateOwnerPromoCodeSupabase(
  promoId: string,
  input: { isActive?: boolean },
): Promise<void> {
  const { error } = await supabase.rpc("update_owner_promo_code", {
    p_promo_id: promoId,
    p_is_active: input.isActive ?? null,
  });
  if (error) throw error;
}

export async function deleteOwnerPromoCodeSupabase(promoId: string): Promise<void> {
  const { error } = await supabase.rpc("delete_owner_promo_code", {
    p_promo_id: promoId,
  });
  if (error) throw error;
}
