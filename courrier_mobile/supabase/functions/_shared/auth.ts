// Copié du dépôt Tibus (supabase/functions/_shared/auth.ts).
import { createClient, User } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function getUserFromRequest(
  req: Request,
): Promise<{ user: User | null; error: string | null }> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return { user: null, error: "Non authentifié" };
  }

  const jwt = authHeader.slice("Bearer ".length).trim();
  if (!jwt) {
    return { user: null, error: "Non authentifié" };
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnon) {
    return { user: null, error: "Configuration Supabase manquante" };
  }

  const client = createClient(supabaseUrl, supabaseAnon);
  const {
    data: { user },
    error: userError,
  } = await client.auth.getUser(jwt);

  if (userError || !user) {
    const detail = userError?.message ?? "Session invalide";
    return { user: null, error: detail };
  }

  return { user, error: null };
}
