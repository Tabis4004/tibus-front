import { jsonResponse } from "../_shared/cors.ts";
import {
  fetchGeniusPayPayment,
  isGeniusPayApproved,
  verifyGeniusPayWebhookSignature,
} from "../_shared/geniuspay.ts";
import { createAdminClient, issueTicketsFromPaymentMetadata } from "../_shared/issue-ticket.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const rawBody = await req.text();
    const signatureOk = await verifyGeniusPayWebhookSignature(req, rawBody);
    if (!signatureOk) {
      return jsonResponse({ error: "Signature webhook invalide" }, 401);
    }

    const payload = JSON.parse(rawBody) as {
      event?: string;
      data?: {
        reference?: string;
        status?: string;
        metadata?: Record<string, string>;
        id?: number | string;
      };
    };

    const event = req.headers.get("X-Webhook-Event") ?? payload.event ?? "";
    if (event !== "payment.success" && payload.data?.status !== "completed") {
      return jsonResponse({ ok: true, skipped: true });
    }

    const reference = payload.data?.reference;
    if (!reference) {
      return jsonResponse({ error: "Référence manquante" }, 400);
    }

    const payment = await fetchGeniusPayPayment(reference);
    if (!payment || !isGeniusPayApproved(payment.status)) {
      return jsonResponse({ ok: true, skipped: true });
    }

    const meta = payment.metadata ?? {};
    if (meta.type !== "supabase_ticket_payment") {
      return jsonResponse({ ok: true, skipped: true });
    }

    if (!meta.reservationId || !meta.appUserId) {
      return jsonResponse({ error: "Metadata incomplète" }, 400);
    }

    const admin = createAdminClient();
    await issueTicketsFromPaymentMetadata(
      admin,
      meta as Record<string, string>,
      String(payment.id ?? payment.reference),
    );

    return jsonResponse({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Webhook error";
    return jsonResponse({ error: message }, 500);
  }
});
