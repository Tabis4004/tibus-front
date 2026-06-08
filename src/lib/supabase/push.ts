import { supabase } from "@/lib/supabase";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

const PUSH_ENDPOINT_KEY = "tibus-push-endpoint";

export type GuaranteePushEvent = "submitted" | "approved" | "rejected";

async function getAccessToken(): Promise<string | null> {
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? null;
}

async function invokeFunction<T>(name: string, body?: unknown): Promise<T> {
  const accessToken = await getAccessToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    apikey: supabaseAnonKey,
  };
  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  }

  const response = await fetch(`${supabaseUrl}/functions/v1/${name}`, {
    method: "POST",
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });

  let payload: (T & { error?: string }) | null = null;
  try {
    payload = (await response.json()) as T & { error?: string };
  } catch {
    payload = null;
  }

  if (!response.ok) {
    throw new Error(payload?.error ?? `Erreur ${name}`);
  }

  return payload as T;
}

export async function getVapidPublicKeySupabase(): Promise<string> {
  const result = await invokeFunction<{ vapidPublicKey: string }>("get-push-config");
  if (!result.vapidPublicKey) {
    throw new Error("Clé VAPID indisponible");
  }
  return result.vapidPublicKey;
}

export async function registerPushSubscriptionSupabase(subscription: PushSubscription): Promise<void> {
  const json = subscription.toJSON();
  const p256dh = json.keys?.p256dh;
  const auth = json.keys?.auth;
  if (!p256dh || !auth) {
    throw new Error("Subscription push invalide");
  }

  const { error } = await supabase.rpc("register_push_subscription", {
    p_endpoint: subscription.endpoint,
    p_p256dh: p256dh,
    p_auth: auth,
  });
  if (error) throw error;

  localStorage.setItem(PUSH_ENDPOINT_KEY, subscription.endpoint);
}

export async function unregisterPushSubscriptionSupabase(endpoint: string): Promise<void> {
  const { error } = await supabase.rpc("unregister_push_subscription", {
    p_endpoint: endpoint,
  });
  if (error) throw error;
  localStorage.removeItem(PUSH_ENDPOINT_KEY);
}

export function getStoredPushEndpoint(): string | null {
  return localStorage.getItem(PUSH_ENDPOINT_KEY);
}

export async function sendGuaranteeDepositPushSupabase(input: {
  depositId: string;
  event: GuaranteePushEvent;
}): Promise<void> {
  try {
    await invokeFunction<{ sent?: number }>("send-push", input);
  } catch {
    // Push optionnel : ne bloque pas le workflow métier
  }
}
