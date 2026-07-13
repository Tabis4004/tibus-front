// Envoie une notification push (FCM) à tous les utilisateurs abonnés au
// suivi d'un colis donné (table ColisTrackingSubscriptions, voir migration
// 2002). Appelée par le client juste après un changement de statut réussi
// (même pattern que colis-sms-notify côté Tibus : le client orchestre,
// l'edge function exécute avec les privilèges nécessaires).
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/admin-client.ts";
import { getUserFromRequest } from "../_shared/auth.ts";
import { sendFcmToTokens } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Méthode non supportée" }, 405);
  }

  const { user, error: authError } = await getUserFromRequest(req);
  if (!user) {
    return jsonResponse({ error: authError ?? "Non authentifié" }, 401);
  }

  let body: { colisId?: string; title?: string; message?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Corps de requête invalide" }, 400);
  }

  const { colisId, title, message } = body;
  if (!colisId || !title || !message) {
    return jsonResponse({ error: "colisId, title et message sont requis" }, 400);
  }

  const admin = createAdminClient();

  // Vérifie que le colis existe (borne l'appel à un colis réel — la
  // véritable autorisation métier reste côté RPC get_colis_autonome_detail,
  // déjà utilisée par l'app avant d'arriver ici).
  const { data: colis, error: colisError } = await admin
    .from("colis_autonomes")
    .select("id")
    .eq("id", colisId)
    .maybeSingle();
  if (colisError) return jsonResponse({ error: colisError.message }, 500);
  if (!colis) return jsonResponse({ error: "Colis introuvable" }, 404);

  const { data: subs, error: subsError } = await admin
    .from("ColisTrackingSubscriptions")
    .select("userId")
    .eq("colisId", colisId);
  if (subsError) return jsonResponse({ error: subsError.message }, 500);

  const userIds = (subs ?? []).map((s) => s.userId as string);
  if (userIds.length === 0) {
    return jsonResponse({ sent: 0, note: "Aucun abonné à ce colis" });
  }

  const { data: tokens, error: tokensError } = await admin
    .from("DeviceTokens")
    .select("fcmToken, platform")
    .in("userId", userIds);
  if (tokensError) return jsonResponse({ error: tokensError.message }, 500);

  const targets = (tokens ?? []).map((t) => ({
    fcmToken: t.fcmToken as string,
    platform: t.platform as "android" | "ios",
  }));

  try {
    const { sent, staleTokens } = await sendFcmToTokens(targets, {
      title,
      body: message,
      data: { colisId, type: "colis_status_update" },
    });

    if (staleTokens.length > 0) {
      await admin.from("DeviceTokens").delete().in("fcmToken", staleTokens);
    }

    return jsonResponse({ sent, staleTokens: staleTokens.length });
  } catch (error) {
    console.error("[send-colis-push] error", error);
    return jsonResponse(
      { error: (error as Error).message ?? "Envoi push impossible" },
      503,
    );
  }
});
