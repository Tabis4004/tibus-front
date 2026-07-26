// Réinitialisation directe du mot de passe d'un utilisateur par le
// super_admin — même schéma que admin-provision-user (service role côté
// Edge Function, seul moyen d'appeler auth.admin.updateUserById puisque le
// SDK client n'expose pas cette API pour un compte tiers).
//
// Helpers auth/cors/admin-client dupliqués ici (au lieu d'importer
// ../_shared/*) : le bundler de déploiement MCP ne résout pas les imports
// relatifs sortant du dossier de la fonction, contrairement à
// `supabase functions deploy` en CLI local.
import { createClient, SupabaseClient, User } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-api-key",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function getUserFromRequest(
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

function createAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error("SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY manquant");
  }
  return createClient(url, serviceKey);
}

async function resolveAppUserId(
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

type ResetPasswordBody = {
  userId?: string;
  newPassword?: string;
};

async function isSuperAdmin(
  admin: SupabaseClient,
  appUserId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("UserRoles")
    .select("Role(name)")
    .eq("userId", appUserId);

  if (error) throw error;

  return (data ?? []).some((row) => {
    const role = Array.isArray(row.Role) ? row.Role[0] : row.Role;
    return (role as { name?: string } | null)?.name === "super_admin";
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user, error: authError } = await getUserFromRequest(req);
    if (authError || !user) {
      return jsonResponse({ error: authError ?? "Session invalide" }, 401);
    }

    const body = (await req.json()) as ResetPasswordBody;
    const targetUserId = body.userId?.trim();
    const newPassword = body.newPassword?.trim();

    if (!targetUserId || !newPassword) {
      return jsonResponse({ error: "Utilisateur et nouveau mot de passe requis" }, 400);
    }
    if (newPassword.length < 6) {
      return jsonResponse({ error: "Mot de passe trop court (min. 6 caractères)" }, 400);
    }

    const admin = createAdminClient();
    const appUserId = await resolveAppUserId(admin, user.id);
    if (!appUserId) {
      return jsonResponse({ error: "Utilisateur introuvable" }, 403);
    }

    const superAdmin = await isSuperAdmin(admin, appUserId);
    if (!superAdmin) {
      return jsonResponse({ error: "Action réservée au super_admin" }, 403);
    }

    const { data: targetProfile, error: targetError } = await admin
      .from("Users")
      .select("id, auth_user_id, firstName, lastName, email")
      .eq("id", targetUserId)
      .maybeSingle();

    if (targetError) throw targetError;
    if (!targetProfile?.auth_user_id) {
      return jsonResponse({ error: "Utilisateur cible introuvable" }, 404);
    }

    const { error: updateError } = await admin.auth.admin.updateUserById(
      targetProfile.auth_user_id as string,
      { password: newPassword },
    );

    if (updateError) {
      return jsonResponse({ error: updateError.message ?? "Mise à jour du mot de passe impossible" }, 400);
    }

    return jsonResponse({
      success: true,
      user: {
        id: targetProfile.id,
        firstName: targetProfile.firstName,
        lastName: targetProfile.lastName,
        email: targetProfile.email,
      },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Erreur mise à jour mot de passe";
    return jsonResponse({ error: msg }, 500);
  }
});
