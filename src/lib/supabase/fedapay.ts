import { supabase } from "@/lib/supabase";
import type { PaymentNetwork } from "@/config/commission.ts";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

export type InitializeFedaPayTraveler = {
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string;
  parcelCount?: number;
  parcelWeight?: number;
  parcelAmount?: number;
};

export type InitializeFedaPayParams = {
  reservationId: string;
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string;
  travelers?: InitializeFedaPayTraveler[];
  channel?: "traveler" | "seller_reservation";
  promoId?: string;
  discountAmount?: number;
  loyaltyPointsRedeemed?: number;
  loyaltyDiscountAmount?: number;
  platformLoyaltyPointsRedeemed?: number;
  platformLoyaltyDiscountAmount?: number;
  paymentMethod?: "mobile_money" | "card" | "bank_transfer" | "wallet";
  paymentNetwork?: PaymentNetwork;
  paymentCountryId?: string;
  successUrl: string;
  errorUrl: string;
};

export type InitializeFedaPayResult = {
  checkoutUrl: string;
  reference: string;
  transactionId: string;
  amount: number;
  nominalAmount?: number;
};

export type VerifyFedaPayParams = {
  transactionId?: string;
  reference?: string;
  reservationId?: string;
  gateway?: string;
};

export type VerifyFedaPayResult = {
  success: boolean;
  bookingId?: string;
  bookingIds?: string[];
  reference?: string;
  references?: string[];
  error?: string;
  code?: string;
};

function isRefreshTokenError(message?: string) {
  if (!message) return false;
  const lower = message.toLowerCase();
  return lower.includes("refresh token") || lower.includes("invalid credentials");
}

async function clearBrokenSession() {
  try {
    await supabase.auth.signOut();
  } catch {
    localStorage.removeItem("sb-kqudaqtydimjclwaihqr-auth-token");
  }
}

async function getAccessToken(): Promise<string> {
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();

  if (sessionError && isRefreshTokenError(sessionError.message)) {
    await clearBrokenSession();
    throw new Error("Session expirée — reconnectez-vous");
  }

  let session = sessionData.session;
  if (!session?.access_token) {
    throw new Error("Connectez-vous pour payer");
  }

  const now = Math.floor(Date.now() / 1000);
  const exp = session.expires_at ?? 0;

  if (exp > now) {
    const shouldRefresh = exp - now < 120 && Boolean(session.refresh_token);
    if (shouldRefresh) {
      const { data: refreshed, error: refreshError } =
        await supabase.auth.refreshSession();
      if (!refreshError && refreshed.session?.access_token) {
        return refreshed.session.access_token;
      }
      if (refreshError && isRefreshTokenError(refreshError.message)) {
        await clearBrokenSession();
        throw new Error("Session expirée — reconnectez-vous");
      }
    }
    return session.access_token;
  }

  if (!session.refresh_token) {
    await clearBrokenSession();
    throw new Error("Session expirée — reconnectez-vous");
  }

  const { data: refreshed, error: refreshError } =
    await supabase.auth.refreshSession();
  if (refreshError || !refreshed.session?.access_token) {
    await clearBrokenSession();
    throw new Error("Session expirée — reconnectez-vous");
  }

  return refreshed.session.access_token;
}

async function invokeFunction<T>(name: string, body: unknown): Promise<T> {
  const accessToken = await getAccessToken();

  const response = await fetch(`${supabaseUrl}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      apikey: supabaseAnonKey,
    },
    body: JSON.stringify(body),
  });

  let payload: (T & { error?: string; code?: string; message?: string }) | null =
    null;
  try {
    payload = (await response.json()) as T & {
      error?: string;
      code?: string;
      message?: string;
    };
  } catch {
    payload = null;
  }

  if (!response.ok) {
    let message =
      payload?.error ??
      payload?.message ??
      `Erreur ${name} (${response.status})`;

    if (message.includes("phone_number") || message.includes("téléphone")) {
      message =
        "Numéro de téléphone invalide — utilisez 10 chiffres ivoiriens (ex: 07 00 00 00 00)";
    } else if (message.startsWith("FedaPay transaction failed:")) {
      try {
        const jsonPart = message.slice("FedaPay transaction failed:".length).trim();
        const fp = JSON.parse(jsonPart) as { message?: string; errors?: Record<string, string[]> };
        if (fp.errors?.["phone_number.number"]?.[0] || fp.errors?.phone_number?.[0]) {
          message =
            "Numéro de téléphone invalide — utilisez 10 chiffres ivoiriens (ex: 07 00 00 00 00)";
        } else if (fp.message) {
          message = fp.message;
        }
      } catch {
        // keep original
      }
    }
    const err = new Error(message) as Error & { code?: string };
    err.code = payload?.code;
    throw err;
  }

  if (payload && typeof payload === "object" && "error" in payload && payload.error) {
    const err = new Error(payload.error) as Error & { code?: string };
    err.code = payload.code;
    throw err;
  }

  return payload as T;
}

export async function initializeFedaPaySupabase(
  params: InitializeFedaPayParams,
): Promise<InitializeFedaPayResult> {
  return invokeFunction<InitializeFedaPayResult>("payment-initialize", params);
}

export async function verifyFedaPaySupabase(
  params: VerifyFedaPayParams,
): Promise<VerifyFedaPayResult> {
  return invokeFunction<VerifyFedaPayResult>("payment-verify", params);
}
