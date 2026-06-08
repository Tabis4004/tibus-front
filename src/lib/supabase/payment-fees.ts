import {
  type PaymentBreakdown,
  type PaymentGateway,
  type PaymentMethod,
  type PaymentNetwork,
} from "@/config/commission.ts";
import { supabase } from "@/lib/supabase";

export type GatewayPaymentFeeSetting = {
  id: string;
  gateway: PaymentGateway;
  countryId: string;
  countryName: string;
  method: PaymentMethod;
  network: string;
  yPercent: number;
  zPercent: number | null;
  fFixed: number | null;
  isActive: boolean;
  updatedAt: string | null;
  updatedByName: string | null;
};

type GatewayFeeRpcRow = {
  id: unknown;
  gateway: unknown;
  country_id: unknown;
  country_name: unknown;
  method: unknown;
  network: unknown;
  y_percent: unknown;
  z_percent: unknown;
  f_fixed: unknown;
  is_active: unknown;
  updated_at: unknown;
  updated_by_name: unknown;
};

type PaymentBreakdownJson = {
  nominalAmount?: unknown;
  platformMarginPercent?: unknown;
  platformNetAmount?: unknown;
  gatewayFeePercent?: unknown;
  geniusPayFeePercent?: unknown;
  fixedFee?: unknown;
  rawTotalAmount?: unknown;
  totalAmount?: unknown;
  paidBy?: unknown;
  marginScope?: unknown;
  network?: unknown;
  requestedNetwork?: unknown;
  usedMaxFallback?: unknown;
  gatewayAmount?: unknown;
  feeMode?: unknown;
};

function numberValue(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeBreakdown(payload: PaymentBreakdownJson): PaymentBreakdown {
  const paidBy = String(payload.paidBy ?? "company");
  return {
    nominalAmount: numberValue(payload.nominalAmount),
    platformMarginPercent: numberValue(payload.platformMarginPercent),
    platformNetAmount: numberValue(payload.platformNetAmount),
    gatewayFeePercent: numberValue(payload.gatewayFeePercent),
    geniusPayFeePercent: numberValue(payload.geniusPayFeePercent),
    fixedFee: numberValue(payload.fixedFee),
    rawTotalAmount: numberValue(payload.rawTotalAmount),
    totalAmount: numberValue(payload.totalAmount),
    paidBy: paidBy === "traveler" ? "traveler" : "company",
    marginScope: String(payload.marginScope ?? "unset"),
    network: payload.network ? String(payload.network) : undefined,
    requestedNetwork: payload.requestedNetwork
      ? String(payload.requestedNetwork)
      : undefined,
    usedMaxFallback: payload.usedMaxFallback != null
      ? Boolean(payload.usedMaxFallback)
      : undefined,
    gatewayAmount: payload.gatewayAmount != null
      ? numberValue(payload.gatewayAmount)
      : undefined,
    feeMode: payload.feeMode === "on_top" || payload.feeMode === "deducted"
      ? payload.feeMode
      : undefined,
  };
}

function normalizeGatewayFee(row: GatewayFeeRpcRow): GatewayPaymentFeeSetting {
  return {
    id: String(row.id),
    gateway: String(row.gateway) as PaymentGateway,
    countryId: String(row.country_id),
    countryName: String(row.country_name ?? ""),
    method: String(row.method) as PaymentMethod,
    network: String(row.network ?? "default"),
    yPercent: numberValue(row.y_percent),
    zPercent: row.z_percent == null ? null : numberValue(row.z_percent),
    fFixed: row.f_fixed == null ? null : numberValue(row.f_fixed),
    isActive: Boolean(row.is_active),
    updatedAt: row.updated_at ? String(row.updated_at) : null,
    updatedByName: row.updated_by_name ? String(row.updated_by_name) : null,
  };
}

export async function listGatewayPaymentFeesSupabase(): Promise<GatewayPaymentFeeSetting[]> {
  const { data, error } = await supabase.rpc("list_gateway_payment_fees");
  if (error) throw error;
  return ((data ?? []) as GatewayFeeRpcRow[]).map(normalizeGatewayFee);
}

export async function upsertGatewayPaymentFeeSupabase(params: {
  gateway: PaymentGateway;
  countryId: string;
  method: PaymentMethod;
  network?: string;
  yPercent: number;
  zPercent?: number | null;
  fFixed?: number | null;
  isActive?: boolean;
}): Promise<GatewayPaymentFeeSetting | null> {
  const { data, error } = await supabase.rpc("upsert_gateway_payment_fee", {
    p_gateway: params.gateway,
    p_country_id: params.countryId,
    p_method: params.method,
    p_network: params.network ?? "default",
    p_y_percent: params.yPercent,
    p_z_percent: params.zPercent ?? null,
    p_f_fixed: params.fFixed ?? null,
    p_is_active: params.isActive ?? true,
  });
  if (error) throw error;
  const rows = (data ?? []) as GatewayFeeRpcRow[];
  return rows[0] ? normalizeGatewayFee(rows[0]) : null;
}

export async function deleteGatewayPaymentFeeSupabase(feeId: string): Promise<void> {
  const { error } = await supabase.rpc("delete_gateway_payment_fee", {
    p_fee_id: feeId,
  });
  if (error) throw error;
}

export type TravelerPaymentInput = {
  nominalAmount: number;
  companyId: string;
  gateway?: PaymentGateway;
  method?: PaymentMethod;
  network?: PaymentNetwork | null;
  tripMarginPercent?: number | null;
};

export async function calculateTravelerPaymentSupabase(
  input: TravelerPaymentInput,
): Promise<PaymentBreakdown> {
  const { data, error } = await supabase.rpc("calculate_traveler_payment_total", {
    p_nominal_amount: input.nominalAmount,
    p_company_id: input.companyId,
    p_gateway: input.gateway ?? "fedapay",
    p_method: input.method ?? "mobile_money",
    p_network: input.network ?? "unknown",
    p_trip_margin_percent: input.tripMarginPercent ?? null,
  });

  if (error) throw error;
  return normalizeBreakdown((data ?? {}) as PaymentBreakdownJson);
}
