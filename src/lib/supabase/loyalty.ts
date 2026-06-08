import { supabase } from "@/lib/supabase";

export type CompanyLoyaltySettings = {
  companyId: string;
  isActive: boolean;
  spendUnitAmount: number;
  pointsPerSpendUnit: number;
  discountPerPoint: number;
  minRedeemPoints: number;
  maxRedeemPercent: number;
  updatedAt?: string | null;
};

export type TravelerLoyaltyContext = {
  active: boolean;
  pointsBalance: number;
  spendUnitAmount?: number;
  pointsPerSpendUnit?: number;
  discountPerPoint?: number;
  minRedeemPoints?: number;
  maxRedeemPercent?: number;
};

export type LoyaltyRedemptionResult = {
  valid: boolean;
  discountAmount?: number;
  pointsRedeemed?: number;
  error?: string;
};

function mapSettings(data: Record<string, unknown>): CompanyLoyaltySettings {
  return {
    companyId: String(data.companyId ?? ""),
    isActive: Boolean(data.isActive),
    spendUnitAmount: Number(data.spendUnitAmount ?? 1000),
    pointsPerSpendUnit: Number(data.pointsPerSpendUnit ?? 1),
    discountPerPoint: Number(data.discountPerPoint ?? 50),
    minRedeemPoints: Number(data.minRedeemPoints ?? 10),
    maxRedeemPercent: Number(data.maxRedeemPercent ?? 50),
    updatedAt: data.updatedAt ? String(data.updatedAt) : null,
  };
}

export async function getCompanyLoyaltySettingsSupabase(
  companyId: string,
): Promise<CompanyLoyaltySettings> {
  const { data, error } = await supabase.rpc("get_company_loyalty_settings", {
    p_company_id: companyId,
  });
  if (error) throw error;
  return mapSettings((data ?? {}) as Record<string, unknown>);
}

export async function upsertCompanyLoyaltySettingsSupabase(
  companyId: string,
  input: Omit<CompanyLoyaltySettings, "companyId" | "updatedAt">,
): Promise<CompanyLoyaltySettings> {
  const { data, error } = await supabase.rpc("upsert_company_loyalty_settings", {
    p_company_id: companyId,
    p_is_active: input.isActive,
    p_spend_unit_amount: input.spendUnitAmount,
    p_points_per_spend_unit: input.pointsPerSpendUnit,
    p_discount_per_point: input.discountPerPoint,
    p_min_redeem_points: input.minRedeemPoints,
    p_max_redeem_percent: input.maxRedeemPercent,
  });
  if (error) throw error;
  return mapSettings((data ?? {}) as Record<string, unknown>);
}

export async function getTravelerLoyaltyContextSupabase(
  companyId: string,
): Promise<TravelerLoyaltyContext> {
  const { data, error } = await supabase.rpc("get_traveler_loyalty_context", {
    p_company_id: companyId,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    active: Boolean(row.active),
    pointsBalance: Number(row.pointsBalance ?? 0),
    spendUnitAmount: row.spendUnitAmount != null ? Number(row.spendUnitAmount) : undefined,
    pointsPerSpendUnit: row.pointsPerSpendUnit != null ? Number(row.pointsPerSpendUnit) : undefined,
    discountPerPoint: row.discountPerPoint != null ? Number(row.discountPerPoint) : undefined,
    minRedeemPoints: row.minRedeemPoints != null ? Number(row.minRedeemPoints) : undefined,
    maxRedeemPercent: row.maxRedeemPercent != null ? Number(row.maxRedeemPercent) : undefined,
  };
}

export async function validateLoyaltyRedemptionSupabase(
  companyId: string,
  ticketPrice: number,
  points: number,
): Promise<LoyaltyRedemptionResult> {
  const { data, error } = await supabase.rpc("validate_loyalty_redemption", {
    p_company_id: companyId,
    p_ticket_price: ticketPrice,
    p_points: points,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    valid: Boolean(row.valid),
    discountAmount: row.discountAmount != null ? Number(row.discountAmount) : undefined,
    pointsRedeemed: row.pointsRedeemed != null ? Number(row.pointsRedeemed) : undefined,
    error: row.error ? String(row.error) : undefined,
  };
}
