import { getUserFromRequest } from "../_shared/auth.ts";
import {
  normalizePhoneForAt,
  sendAfricasTalkingSms,
} from "../_shared/africastalking-sms.ts";
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

    const { data: companyRow } = await admin
      .from("Companies")
      .select("Countries(name)")
      .eq("id", colis.company_id as string)
      .maybeSingle();

    const countryName = String(
      (companyRow?.Countries as { name?: string } | null)?.name ?? "",
    )
      .toLowerCase()
      .normalize("NFD")
      .replace(/\p{M}/gu, "");

    const countryCode = (() => {
      if (countryName.includes("ivoire") || countryName.includes("ivory")) return "CI";
      if (countryName.includes("benin")) return "BJ";
      if (countryName.includes("burkina")) return "BF";
      if (countryName.includes("senegal")) return "SN";
      if (countryName.includes("togo")) return "TG";
      if (countryName.includes("mali")) return "ML";
      if (countryName.includes("ghana")) return "GH";
      return Deno.env.get("AT_DEFAULT_COUNTRY") ?? "CI";
    })();

    const { data: allowed } = await admin.rpc("is_company_role_user", {
      p_user_id: appUserId,
      p_company_id: colis.company_id as string,
    });

    if (!allowed) {
      return jsonResponse({ error: "Droits insuffisants" }, 403);
    }

    const uniquePhones = [...new Set(phones)];
    const deliveryResults: Array<{ phone: string; ok: boolean; error?: string }> = [];

    for (const rawPhone of uniquePhones) {
      const to = normalizePhoneForAt(rawPhone, countryCode);
      if (!to) {
        deliveryResults.push({ phone: rawPhone, ok: false, error: "Numéro invalide" });
        continue;
      }

      const result = await sendAfricasTalkingSms(to, message);
      if (result.ok) {
        deliveryResults.push({ phone: to, ok: true });
        continue;
      }

      console.error("[colis-sms]", { colisId, phone: to, error: result.body });
      deliveryResults.push({
        phone: to,
        ok: false,
        error: result.errorMessage ?? "Échec envoi SMS",
      });
    }

    const sent = deliveryResults.filter((r) => r.ok).length;
    const failed = deliveryResults.filter((r) => !r.ok);

    if (sent === 0) {
      return jsonResponse(
        {
          error: "Aucun SMS envoyé",
          colisId,
          statut: body.statut,
          failures: failed,
        },
        502,
      );
    }

    return jsonResponse({
      success: true,
      sent,
      failed: failed.length,
      failures: failed.length ? failed : undefined,
      colisId,
      statut: body.statut,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Erreur SMS colis";
    return jsonResponse({ error: msg }, 500);
  }
});
