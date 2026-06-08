import { getUserFromRequest } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { fetchFedaPayTransaction, isFedaPayApproved } from "../_shared/fedapay.ts";
import {
  createAdminClient,
  issueTicketsFromPaymentMetadata,
  resolveAppUserId,
} from "../_shared/issue-ticket.ts";

type VerifyBody = {
  transactionId?: string;
  reference?: string;
  reservationId?: string;
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

    const body = (await req.json()) as VerifyBody;
    const txn = await fetchFedaPayTransaction({
      transactionId: body.transactionId,
      reference: body.reference,
    });

    if (!txn || !isFedaPayApproved(txn.status)) {
      return jsonResponse({ success: false });
    }

    const meta = txn.custom_metadata ?? {};
    if (meta.type !== "supabase_ticket_payment") {
      return jsonResponse({ success: false, error: "Type de paiement invalide" }, 400);
    }

    const appUserId = await resolveAppUserId(createAdminClient(), user.id);
    if (!appUserId || meta.appUserId !== appUserId) {
      return jsonResponse({ error: "Paiement non autorisé" }, 403);
    }

    if (body.reservationId && meta.reservationId !== body.reservationId) {
      return jsonResponse({ error: "Départ incompatible" }, 400);
    }

    const admin = createAdminClient();
    const issued = await issueTicketsFromPaymentMetadata(
      admin,
      meta as Record<string, string>,
      String(txn.id ?? body.transactionId ?? txn.reference),
    );

    return jsonResponse({
      success: true,
      bookingId: issued[0]?.bookingId,
      bookingIds: issued.map((ticket) => ticket.bookingId),
      reference: issued[0]?.reference,
      references: issued.map((ticket) => ticket.reference),
      alreadyIssued: issued.every((ticket) => ticket.alreadyIssued),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erreur vérification";
    if (message.includes("Plus de places")) {
      return jsonResponse({ success: false, error: message, code: "SOLD_OUT" }, 409);
    }
    return jsonResponse({ success: false, error: message }, 500);
  }
});
