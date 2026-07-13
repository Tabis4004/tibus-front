// Copié du dépôt Tibus (supabase/functions/_shared/admin-client.ts).
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export function createAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error("SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY manquant");
  }
  return createClient(url, serviceKey);
}

export async function resolveAppUserId(
  admin: SupabaseClient,
  authUserId: string,
): Promise<string | null> {
  const { data, error } = await admin
    .from("Users")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();

  if (error) throw error;
  return (data?.id as string) ?? null;
}
