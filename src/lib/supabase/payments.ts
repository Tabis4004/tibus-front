import type { PaymentGateway } from "@/config/commission.ts";
import {
  getActivePaymentGatewaySupabase,
  type ActivePaymentGateway,
} from "@/lib/supabase/payment-gateway.ts";
import {
  initializeFedaPaySupabase,
  verifyFedaPaySupabase,
  type InitializeFedaPayParams,
  type InitializeFedaPayResult,
  type VerifyFedaPayParams,
  type VerifyFedaPayResult,
} from "@/lib/supabase/fedapay.ts";

export type InitializePaymentResult = InitializeFedaPayResult & {
  gateway?: ActivePaymentGateway;
};

export async function initializePaymentSupabase(
  params: InitializeFedaPayParams,
): Promise<InitializePaymentResult> {
  return initializeFedaPaySupabase(params);
}

export async function verifyPaymentSupabase(
  params: VerifyFedaPayParams & { gateway?: PaymentGateway | string },
): Promise<VerifyFedaPayResult & { gateway?: string }> {
  return verifyFedaPaySupabase(params);
}

export async function resolveTravelerPaymentGateway(
  override?: PaymentGateway,
): Promise<ActivePaymentGateway> {
  if (override === "geniuspay" || override === "fedapay") return override;
  const active = await getActivePaymentGatewaySupabase();
  return active.gateway;
}
