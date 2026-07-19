// Push FCM générique vers une liste d'utilisateurs staff d'UNE compagnie
// (owner/comptable_compagnie/gerant_gare) — déclenché par le client (web ou
// mobile) juste après un appel réussi à register_colis_autonome /
// update_colis_autonome_statut / mark_bordereau_charge / mark_bordereau_arrive
// / cancel_colis_autonome (migration 190), qui renvoient déjà
// notifyRecipients/notifyTitle/notifyMessage calculés côté base avec le
// même scoping par rôle que get_colis_autonome_stats. Même pattern que
// colis-sms-notify / send-colis-push : le serveur (RPC) prépare la liste de
// destinataires, le client orchestre, cette edge function exécute l'envoi
// avec les privilèges nécessaires (secret FCM_SERVICE_ACCOUNT).
//
// Garde-fou : on ne fait PAS confiance aveuglément à la liste d'IDs fournie
// par le client — on revérifie que chaque destinataire appartient bien à la
// même compagnie que l'appelant (UserRoles."companyId"), pour empêcher un
// appelant authentifié de faire pousser une notification vers des
// utilisateurs d'une autre compagnie.
import { getUserFromRequest } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient, resolveAppUserId } from "../_shared/admin-client.ts";
import { sendFcmToTokens } from "../_shared/fcm.ts";

type SendStaffPushBody = {
  userIds?: string[];
  companyId?: string;
  title?: string;
  message?: string;
  data?: Record<string, string>;
};

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

  let body: SendStaffPushBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Corps de requête invalide" }, 400);
  }

  const { companyId, title, message } = body;
  const userIds = [...new Set((body.userIds ?? []).filter(Boolean))];

  if (!companyId || !title || !message) {
    return jsonResponse({ error: "companyId, title et message sont requis" }, 400);
  }
  if (userIds.length === 0) {
    return jsonResponse({ sent: 0, note: "Aucun destinataire" });
  }

  const admin = createAdminClient();
  const appUserId = await resolveAppUserId(admin, user.id);
  if (!appUserId) {
    return jsonResponse({ error: "Profil utilisateur introuvable" }, 403);
  }

  const { data: allowed, error: allowedError } = await admin.rpc("is_company_role_user", {
    p_user_id: appUserId,
    p_company_id: companyId,
  });
  if (allowedError) return jsonResponse({ error: allowedError.message }, 500);
  if (!allowed) {
    return jsonResponse({ error: "Droits insuffisants pour cette compagnie" }, 403);
  }

  // Ne garde que les destinataires réellement rattachés à companyId —
  // empêche un client de forger une liste d'IDs hors compagnie.
  const { data: companyUserRows, error: companyUsersError } = await admin
    .from("UserRoles")
    .select("userId")
    .eq("companyId", companyId)
    .in("userId", userIds);
  if (companyUsersError) return jsonResponse({ error: companyUsersError.message }, 500);

  const scopedUserIds = [...new Set((companyUserRows ?? []).map((r) => r.userId as string))];
  if (scopedUserIds.length === 0) {
    return jsonResponse({ sent: 0, note: "Aucun destinataire valide pour cette compagnie" });
  }

  const { data: tokens, error: tokensError } = await admin
    .from("DeviceTokens")
    .select("fcmToken, platform")
    .in("userId", scopedUserIds);
  if (tokensError) return jsonResponse({ error: tokensError.message }, 500);

  const targets = (tokens ?? []).map((t) => ({
    fcmToken: t.fcmToken as string,
    platform: t.platform as "android" | "ios",
  }));

  if (targets.length === 0) {
    return jsonResponse({ sent: 0, note: "Aucun appareil enregistré pour ces destinataires" });
  }

  try {
    const { sent, staleTokens } = await sendFcmToTokens(targets, {
      title,
      body: message,
      data: { ...(body.data ?? {}), companyId, type: "staff_colis_notification" },
    });

    if (staleTokens.length > 0) {
      await admin.from("DeviceTokens").delete().in("fcmToken", staleTokens);
    }

    return jsonResponse({ sent, staleTokens: staleTokens.length });
  } catch (error) {
    console.error("[send-staff-push] error", error);
    return jsonResponse(
      { error: (error as Error).message ?? "Envoi push impossible" },
      503,
    );
  }
});
