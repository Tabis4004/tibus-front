import { jsonResponse } from "../_shared/cors.ts";
import { fetchFedaPayTransaction, isFedaPayApproved } from "../_shared/fedapay.ts";
import { createAdminClient, issueTicketsFromPaymentMetadata } from "../_shared/issue-ticket.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const payload = await req.json() as {
      object?: string;
      entity?: {
        id?: number | string;
        reference?: string;
        status?: string;
        custom_metadata?: Record<string, string>;
      };
    };

    if (payload.object !== "transaction") {
      return jsonResponse({ ok: true, skipped: true });
    }

    const txn = payload.entity;
    if (!txn || !isFedaPayApproved(txn.status)) {
      return jsonResponse({ ok: true, skipped: true });
    }

    const verifiedTxn = await fetchFedaPayTransaction({
      transactionId: txn.id ? String(txn.id) : undefined,
      reference: txn.reference,
    });
    if (!verifiedTxn || !isFedaPayApproved(verifiedTxn.status)) {
      return jsonResponse({ ok: true, skipped: true });
    }

    const meta = verifiedTxn.custom_metadata ?? {};
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
      String(verifiedTxn.id ?? verifiedTxn.reference),
    );

    return jsonResponse({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Webhook error";
    return jsonResponse({ error: message }, 500);
  }
});
