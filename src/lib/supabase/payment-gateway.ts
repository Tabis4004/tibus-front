import { supabase } from "@/lib/supabase";
import type { PaymentGateway } from "@/config/commission.ts";

export type ActivePaymentGateway = Extract<PaymentGateway, "fedapay" | "geniuspay">;

export type ActivePaymentGatewayState = {
  gateway: ActivePaymentGateway;
  updatedAt: string | null;
};

function normalizeGateway(value: unknown): ActivePaymentGateway {
  return String(value ?? "fedapay").toLowerCase() === "geniuspay"
    ? "geniuspay"
    : "fedapay";
}

export async function getActivePaymentGatewaySupabase(): Promise<ActivePaymentGatewayState> {
  const { data, error } = await supabase.rpc("get_active_payment_gateway");
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    gateway: normalizeGateway(row.gateway),
    updatedAt: row.updatedAt ? String(row.updatedAt) : null,
  };
}

export async function setActivePaymentGatewaySupabase(
  gateway: ActivePaymentGateway,
): Promise<ActivePaymentGatewayState> {
  const { data, error } = await supabase.rpc("set_active_payment_gateway", {
    p_gateway: gateway,
  });
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    gateway: normalizeGateway(row.gateway),
    updatedAt: row.updatedAt ? String(row.updatedAt) : null,
  };
}
