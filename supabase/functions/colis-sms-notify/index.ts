import { getUserFromRequest } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient, resolveAppUserId } from "../_shared/issue-ticket.ts";

type SmsBody = {
  colisId?: string;
  statut?: string;
  message?: string;
  phones?: string[];
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user, error: authError } = await getUserFromRequest(req);
    if (authError || !user) {
      return jsonResponse({ error: authError ?? "Session invalide" }, 401);
    }

    const body = (await req.json()) as SmsBody;
    const colisId = body.colisId?.trim();
    const message = body.message?.trim();
    const phones = (body.phones ?? []).map((p) => p.trim()).filter(Boolean);

    if (!colisId || !message || !phones.length) {
      return jsonResponse({ error: "Paramètres SMS incomplets" }, 400);
    }

    const admin = createAdminClient();
    const appUserId = await resolveAppUserId(admin, user.id);

    if (!appUserId) {
      return jsonResponse({ error: "Utilisateur introuvable" }, 403);
    }

    const { data: colis, error: colisError } = await admin
      .from("colis_autonomes")
      .select("id, company_id")
      .eq("id", colisId)
      .maybeSingle();

    if (colisError) throw colisError;
    if (!colis) {
      return jsonResponse({ error: "Colis introuvable" }, 404);
    }

    const { data: allowed } = await admin.rpc("is_company_role_user", {
      p_user_id: appUserId,
      p_company_id: colis.company_id as string,
    });

    if (!allowed) {
      return jsonResponse({ error: "Droits insuffisants" }, 403);
    }

    // Provider SMS : brancher ici (Twilio, Africa's Talking, etc.)
    // Pour l'instant journalisation serveur + accusé de réception.
    console.log("[colis-sms]", {
      colisId,
      statut: body.statut,
      phones,
      message,
      sentBy: appUserId,
    });

    return jsonResponse({
      success: true,
      queued: phones.length,
      note: "SMS journalise — connecter le fournisseur SMS dans colis-sms-notify",
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Erreur SMS colis";
    return jsonResponse({ error: msg }, 500);
  }
});
