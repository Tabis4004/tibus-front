import { getUserFromRequest } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient, resolveAppUserId } from "../_shared/issue-ticket.ts";
import { sendPushToSubscriptions } from "../_shared/push.ts";

type SendPushBody = {
  depositId?: string;
  event?: "submitted" | "approved" | "rejected";
};

async function getCompanyValidatorIds(
  admin: ReturnType<typeof createAdminClient>,
  companyId: string,
): Promise<string[]> {
  const { data: roles, error: rolesError } = await admin
    .from("Role")
    .select("id")
    .in("name", ["owner", "comptable_compagnie"]);
  if (rolesError) throw rolesError;

  const roleIds = (roles ?? []).map((r) => r.id as string);
  if (roleIds.length === 0) return [];

  const { data: userRoles, error: urError } = await admin
    .from("UserRoles")
    .select("userId")
    .eq("companyId", companyId)
    .in("roleId", roleIds);
  if (urError) throw urError;

  return [...new Set((userRoles ?? []).map((row) => row.userId as string))];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user, error: authError } = await getUserFromRequest(req);
    if (authError || !user) {
      return jsonResponse({ error: authError ?? "Non authentifié" }, 401);
    }

    const body = (await req.json()) as SendPushBody;
    const depositId = body.depositId?.trim();
    const event = body.event;

    if (!depositId || !event) {
      return jsonResponse({ error: "depositId et event requis" }, 400);
    }

    const admin = createAdminClient();
    const appUserId = await resolveAppUserId(admin, user.id);
    if (!appUserId) {
      return jsonResponse({ error: "Profil utilisateur introuvable" }, 403);
    }

    const { data: deposit, error: depositError } = await admin
      .from("CompanyGuaranteeDeposit")
      .select("id, companyId, amount, status, submittedBy")
      .eq("id", depositId)
      .maybeSingle();

    if (depositError) throw depositError;
    if (!deposit) {
      return jsonResponse({ error: "Dépôt introuvable" }, 404);
    }

    const companyId = deposit.companyId as string;
    const amount = Number(deposit.amount);

    const { data: company, error: companyError } = await admin
      .from("Companies")
      .select("name, countryId")
      .eq("id", companyId)
      .maybeSingle();
    if (companyError) throw companyError;

    let currency = "XOF";
    if (company?.countryId) {
      const { data: country } = await admin
        .from("Countries")
        .select("currency")
        .eq("id", company.countryId as string)
        .maybeSingle();
      currency = (country?.currency as string) ?? "XOF";
    }

    const companyName = (company?.name as string) ?? "la compagnie";
    const amountLabel = `${amount.toLocaleString("fr-FR")} ${currency}`;

    let recipientIds: string[] = [];
    let title = "";
    let pushBody = "";
    let url = "/";

    if (event === "submitted") {
      if (deposit.status !== "pending" || deposit.submittedBy !== appUserId) {
        return jsonResponse({ error: "Action non autorisée" }, 403);
      }
      recipientIds = await getCompanyValidatorIds(admin, companyId);
      title = "Dépôt à valider";
      pushBody = `Dépôt de ${amountLabel} — ${companyName}`;
      url = "/company/guarantee-fund";
    } else if (event === "approved") {
      if (deposit.status !== "approved" || !deposit.submittedBy) {
        return jsonResponse({ error: "Dépôt non approuvé" }, 400);
      }
      const validators = await getCompanyValidatorIds(admin, companyId);
      if (!validators.includes(appUserId)) {
        return jsonResponse({ error: "Validation non autorisée" }, 403);
      }
      recipientIds = [deposit.submittedBy as string];
      title = "Dépôt validé";
      pushBody = `Votre dépôt de ${amountLabel} pour ${companyName} a été validé`;
      url = "/admin/guarantee-fund";
    } else if (event === "rejected") {
      if (deposit.status !== "rejected" || !deposit.submittedBy) {
        return jsonResponse({ error: "Dépôt non rejeté" }, 400);
      }
      const validators = await getCompanyValidatorIds(admin, companyId);
      if (!validators.includes(appUserId)) {
        return jsonResponse({ error: "Rejet non autorisé" }, 403);
      }
      recipientIds = [deposit.submittedBy as string];
      title = "Dépôt rejeté";
      pushBody = `Votre dépôt de ${amountLabel} pour ${companyName} a été rejeté`;
      url = "/admin/guarantee-fund";
    } else {
      return jsonResponse({ error: "Event invalide" }, 400);
    }

    if (recipientIds.length === 0) {
      return jsonResponse({ sent: 0, skipped: true });
    }

    const { data: subscriptions, error: subError } = await admin
      .from("UserPushSubscription")
      .select("endpoint, p256dh, auth")
      .in("userId", recipientIds);

    if (subError) throw subError;

    const rows = (subscriptions ?? []) as { endpoint: string; p256dh: string; auth: string }[];
    if (rows.length === 0) {
      return jsonResponse({ sent: 0, skipped: true });
    }

    const { sent, staleEndpoints } = await sendPushToSubscriptions(rows, {
      title,
      body: pushBody,
      url,
    });

    if (staleEndpoints.length > 0) {
      await admin.from("UserPushSubscription").delete().in("endpoint", staleEndpoints);
    }

    return jsonResponse({ sent, recipients: recipientIds.length });
  } catch (error) {
    console.error("send-push error:", error);
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Erreur push" },
      500,
    );
  }
});
