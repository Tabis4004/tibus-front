import { getUserFromRequest } from "../_shared/auth.ts";
import { normalizePhoneForAt, sendAfricasTalkingSms } from "../_shared/africastalking-sms.ts";
import {
  normalizePhoneForInfobip,
  resolveSmsProvider,
  sendInfobipSms,
} from "../_shared/infobip-sms.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient, resolveAppUserId } from "../_shared/admin-client.ts";

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

    const { data: companyRow, error: companyError } = await admin
      .from("Companies")
      .select("countryId, Countries(name)")
      .eq("id", colis.company_id as string)
      .maybeSingle();

    if (companyError) {
      console.error("[colis-sms] company lookup failed", companyError);
    }

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
      return Deno.env.get("SMS_DEFAULT_COUNTRY") ?? Deno.env.get("AT_DEFAULT_COUNTRY") ?? "CI";
    })();

    const { data: allowed } = await admin.rpc("is_company_role_user", {
      p_user_id: appUserId,
      p_company_id: colis.company_id as string,
    });

    if (!allowed) {
      console.error("[colis-sms] forbidden", { appUserId, companyId: colis.company_id });
      return jsonResponse({ error: "Droits insuffisants" }, 403);
    }

    // Verrou par étape (migration 167) : l'étape doit être incluse dans
    // l'offre de la compagnie ET activée par l'owner. Empêche tout envoi
    // forgé contournant l'UI.
    const { data: stepEnabled, error: gateError } = await admin.rpc(
      "colis_sms_enabled_for_statut",
      {
        p_company_id: colis.company_id as string,
        p_statut: String(body.statut ?? ""),
      },
    );

    if (gateError) {
      console.error("[colis-sms] gate check failed", gateError);
      return jsonResponse({ error: "Vérification SMS impossible" }, 500);
    }
    if (!stepEnabled) {
      console.warn("[colis-sms] step not allowed", {
        companyId: colis.company_id,
        statut: body.statut,
      });
      return jsonResponse(
        { error: "Étape SMS non incluse dans l'offre de la compagnie ou désactivée" },
        403,
      );
    }

    const uniquePhones = [...new Set(phones)];
    const provider = resolveSmsProvider();

    if (provider === "infobip") {
      if (!Deno.env.get("INFOBIP_API_KEY")?.trim()) {
        console.error("[colis-sms] missing INFOBIP_API_KEY");
        return jsonResponse({ error: "Configuration SMS Infobip manquante (INFOBIP_API_KEY)" }, 500);
      }
    } else if (!Deno.env.get("AT_USERNAME")?.trim() || !Deno.env.get("AT_API_KEY")?.trim()) {
      console.error("[colis-sms] missing AT secrets");
      return jsonResponse({ error: "Configuration SMS Africa's Talking manquante (AT_USERNAME / AT_API_KEY)" }, 500);
    }

    console.info("[colis-sms] send", {
      colisId,
      statut: body.statut,
      phones: uniquePhones.length,
      provider,
    });

    const deliveryResults: Array<{
      phone: string;
      ok: boolean;
      error?: string;
      messageId?: string;
    }> = [];

    for (const rawPhone of uniquePhones) {
      const toE164 = normalizePhoneForAt(rawPhone, countryCode);
      const toInfobip = normalizePhoneForInfobip(rawPhone, countryCode);
      const to = provider === "infobip" ? toInfobip : toE164;

      if (!to) {
        deliveryResults.push({ phone: rawPhone, ok: false, error: "Numéro invalide" });
        continue;
      }

      const result =
        provider === "infobip"
          ? await sendInfobipSms(to, message)
          : await sendAfricasTalkingSms(toE164!, message);

      if (result.ok) {
        deliveryResults.push({
          phone: provider === "infobip" ? `+${to}` : toE164!,
          ok: true,
          messageId: "messageId" in result ? result.messageId : undefined,
        });
        continue;
      }

      console.error("[colis-sms]", { colisId, phone: to, provider, error: result.body });
      deliveryResults.push({
        phone: provider === "infobip" ? `+${to}` : toE164!,
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
