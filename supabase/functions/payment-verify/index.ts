import { getUserFromRequest } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { fetchFedaPayTransaction, isFedaPayApproved } from "../_shared/fedapay.ts";
import {
  fetchGeniusPayPayment,
  isGeniusPayApproved,
} from "../_shared/geniuspay.ts";
import {
  createAdminClient,
  issueTicketsFromPaymentMetadata,
  resolveAppUserId,
} from "../_shared/issue-ticket.ts";

type VerifyBody = {
  transactionId?: string;
  reference?: string;
  reservationId?: string;
  gateway?: string;
};

function detectGateway(body: VerifyBody): "fedapay" | "geniuspay" {
  const explicit = body.gateway?.trim().toLowerCase();
  if (explicit === "geniuspay" || explicit === "fedapay") {
    return explicit;
  }
  const ref = body.reference?.trim().toUpperCase() ?? "";
  if (ref.startsWith("MTX-")) return "geniuspay";
  return "fedapay";
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

    const body = (await req.json()) as VerifyBody;
    const gateway = detectGateway(body);

    if (gateway === "geniuspay") {
      const reference = body.reference?.trim();
      if (!reference) {
        return jsonResponse({ success: false, error: "Référence GeniusPay manquante" }, 400);
      }

      const payment = await fetchGeniusPayPayment(reference);
      if (!payment || !isGeniusPayApproved(payment.status)) {
        return jsonResponse({ success: false, gateway });
      }

      const meta = payment.metadata ?? {};
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
        String(payment.id ?? payment.reference),
      );

      return jsonResponse({
        success: true,
        gateway,
        bookingId: issued[0]?.bookingId,
        bookingIds: issued.map((ticket) => ticket.bookingId),
        reference: issued[0]?.reference,
        references: issued.map((ticket) => ticket.reference),
        alreadyIssued: issued.every((ticket) => ticket.alreadyIssued),
      });
    }

    const txn = await fetchFedaPayTransaction({
      transactionId: body.transactionId,
      reference: body.reference,
    });

    if (!txn || !isFedaPayApproved(txn.status)) {
      return jsonResponse({ success: false, gateway: "fedapay" });
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
      gateway: "fedapay",
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
