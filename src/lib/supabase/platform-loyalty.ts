import { supabase } from "@/lib/supabase";

export type PlatformLoyaltySettings = {
  scope: string;
  isActive: boolean;
  referralSignupReferrerPoints: number;
  referralSignupNewUserPoints: number;
  referralSharePoints: number;
  referralShareDailyLimit: number;
  spendUnitAmount: number;
  pointsPerSpendUnit: number;
  discountPerPoint: number;
  minRedeemPoints: number;
  maxRedeemPercent: number;
  updatedAt?: string | null;
};

export type ReferralProfile = {
  authenticated: boolean;
  referralCode?: string;
  platformPoints?: number;
  platformActive?: boolean;
  referralSharePoints?: number;
  referralShareDailyLimit?: number;
  sharesToday?: number;
  referredByName?: string;
};

export type CompanyLoyaltyLookupUser = {
  userId: string;
  displayName: string;
  email: string | null;
  phone: string | null;
  companyLoyaltyActive: boolean;
  companyPoints: number;
};

export type LoyaltyBookingContext = {
  company: {
    active: boolean;
    pointsBalance: number;
    discountPerPoint?: number;
    minRedeemPoints?: number;
    maxRedeemPercent?: number;
  };
  platform: {
    active: boolean;
    pointsBalance: number;
    discountPerPoint?: number;
    minRedeemPoints?: number;
    maxRedeemPercent?: number;
    referralCode?: string;
  };
};

export type LoyaltyRedemptionResult = {
  valid: boolean;
  discountAmount?: number;
  pointsRedeemed?: number;
  error?: string;
};

function mapPlatformSettings(data: Record<string, unknown>): PlatformLoyaltySettings {
  return {
    scope: String(data.scope ?? "platform"),
    isActive: Boolean(data.isActive),
    referralSignupReferrerPoints: Number(data.referralSignupReferrerPoints ?? 0),
    referralSignupNewUserPoints: Number(data.referralSignupNewUserPoints ?? 0),
    referralSharePoints: Number(data.referralSharePoints ?? 0),
    referralShareDailyLimit: Number(data.referralShareDailyLimit ?? 1),
    spendUnitAmount: Number(data.spendUnitAmount ?? 1000),
    pointsPerSpendUnit: Number(data.pointsPerSpendUnit ?? 1),
    discountPerPoint: Number(data.discountPerPoint ?? 25),
    minRedeemPoints: Number(data.minRedeemPoints ?? 0),
    maxRedeemPercent: Number(data.maxRedeemPercent ?? 30),
    updatedAt: data.updatedAt ? String(data.updatedAt) : null,
  };
}

export async function getPlatformLoyaltySettingsSupabase(): Promise<PlatformLoyaltySettings> {
  const { data, error } = await supabase.rpc("get_platform_loyalty_settings");
  if (error) throw error;
  return mapPlatformSettings((data ?? {}) as Record<string, unknown>);
}

export async function upsertPlatformLoyaltySettingsSupabase(
  input: Omit<PlatformLoyaltySettings, "scope" | "updatedAt">,
): Promise<PlatformLoyaltySettings> {
  const { data, error } = await supabase.rpc("upsert_platform_loyalty_settings", {
    p_is_active: input.isActive,
    p_spend_unit_amount: input.spendUnitAmount,
    p_points_per_spend_unit: input.pointsPerSpendUnit,
    p_discount_per_point: input.discountPerPoint,
    p_min_redeem_points: input.minRedeemPoints,
    p_max_redeem_percent: input.maxRedeemPercent,
    p_referral_signup_referrer_points: input.referralSignupReferrerPoints,
    p_referral_signup_new_user_points: input.referralSignupNewUserPoints,
    p_referral_share_points: input.referralSharePoints,
    p_referral_share_daily_limit: input.referralShareDailyLimit,
  });
  if (error) throw error;
  return mapPlatformSettings((data ?? {}) as Record<string, unknown>);
}

export async function getMyReferralProfileSupabase(): Promise<ReferralProfile> {
  const { data, error } = await supabase.rpc("get_my_referral_profile");
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    authenticated: Boolean(row.authenticated),
    referralCode: row.referralCode ? String(row.referralCode) : undefined,
    platformPoints: row.platformPointsBalance != null
      ? Number(row.platformPointsBalance)
      : undefined,
    platformActive: row.platformActive != null ? Boolean(row.platformActive) : undefined,
    referralSharePoints: row.referralSharePoints != null
      ? Number(row.referralSharePoints)
      : undefined,
    referralShareDailyLimit: row.referralShareDailyLimit != null
      ? Number(row.referralShareDailyLimit)
      : undefined,
    sharesToday: row.sharesToday != null ? Number(row.sharesToday) : undefined,
    referredByName: row.referredByName ? String(row.referredByName) : undefined,
  };
}

export async function claimReferralSignupSupabase(
  code: string,
): Promise<{ success: boolean; error?: string }> {
  const { data, error } = await supabase.rpc("claim_referral_signup", {
    p_referral_code: code.trim(),
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    success: Boolean(row.success),
    error: row.error ? String(row.error) : undefined,
  };
}

export async function recordReferralShareSupabase(): Promise<{
  success: boolean;
  points?: number;
  error?: string;
}> {
  const { data, error } = await supabase.rpc("record_referral_share");
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    success: Boolean(row.success),
    points: row.pointsCredited != null ? Number(row.pointsCredited) : undefined,
    error: row.error ? String(row.error) : undefined,
  };
}

export async function lookupCompanyLoyaltyUsersSupabase(
  companyId: string,
  query: string,
): Promise<CompanyLoyaltyLookupUser[]> {
  const { data, error } = await supabase.rpc("lookup_company_loyalty_users", {
    p_company_id: companyId,
    p_query: query,
    p_limit: 8,
  });
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  return rows
    .filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === "object")
    .map((row) => ({
      userId: String(row.userId),
      displayName: String(row.displayName ?? ""),
      email: row.email ? String(row.email) : null,
      phone: row.phone ? String(row.phone) : null,
      companyLoyaltyActive: Boolean(row.companyLoyaltyActive),
      companyPoints: Number(row.companyPoints ?? 0),
    }));
}

export async function getLoyaltyBookingContextSupabase(
  companyId: string,
): Promise<LoyaltyBookingContext> {
  const { data, error } = await supabase.rpc("get_loyalty_booking_context", {
    p_company_id: companyId,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  const company = (row.company ?? {}) as Record<string, unknown>;
  const platform = (row.platform ?? {}) as Record<string, unknown>;
  return {
    company: {
      active: Boolean(company.active),
      pointsBalance: Number(company.pointsBalance ?? 0),
      discountPerPoint: company.discountPerPoint != null ? Number(company.discountPerPoint) : undefined,
      minRedeemPoints: company.minRedeemPoints != null ? Number(company.minRedeemPoints) : undefined,
      maxRedeemPercent: company.maxRedeemPercent != null ? Number(company.maxRedeemPercent) : undefined,
    },
    platform: {
      active: Boolean(platform.active),
      pointsBalance: Number(platform.pointsBalance ?? 0),
      discountPerPoint: platform.discountPerPoint != null ? Number(platform.discountPerPoint) : undefined,
      minRedeemPoints: platform.minRedeemPoints != null ? Number(platform.minRedeemPoints) : undefined,
      maxRedeemPercent: platform.maxRedeemPercent != null ? Number(platform.maxRedeemPercent) : undefined,
      referralCode: platform.referralCode ? String(platform.referralCode) : undefined,
    },
  };
}

export async function validatePlatformLoyaltyRedemptionSupabase(
  ticketPrice: number,
  points: number,
  userId?: string,
): Promise<LoyaltyRedemptionResult> {
  const { data, error } = await supabase.rpc("validate_platform_loyalty_redemption", {
    p_ticket_price: ticketPrice,
    p_points: points,
    p_user_id: userId ?? null,
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

export const REFERRAL_STORAGE_KEY = "tibus:referral-code";

export function storeReferralCode(code: string) {
  localStorage.setItem(REFERRAL_STORAGE_KEY, code.trim().toUpperCase());
}

export function readStoredReferralCode(): string | null {
  return localStorage.getItem(REFERRAL_STORAGE_KEY);
}

export function clearStoredReferralCode() {
  localStorage.removeItem(REFERRAL_STORAGE_KEY);
}
