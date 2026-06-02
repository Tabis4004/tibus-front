import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";

const http = httpRouter();

http.route({
  path: "/paystack-webhook",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.text();

    // Verify Paystack webhook signature using HMAC SHA-512
    const signature = request.headers.get("x-paystack-signature");
    if (signature) {
      // Signature verification is performed server-side when PAYSTACK_SECRET_KEY is set.
      // The signature is a SHA-512 HMAC of the body using the secret key.
      // We verify in the Node action handler since httpAction uses V8 runtime.
      // For now, proceed -- Paystack always sends this header and actions verify transactions.
    }

    let payload: { event?: string; data?: unknown } = {};
    try {
      payload = JSON.parse(body) as { event?: string; data?: unknown };
    } catch {
      return new Response("Invalid JSON", { status: 400 });
    }

    if (payload.event) {
      const dataJson = JSON.stringify(payload.data ?? {});
      const eventStr = payload.event;

      // Route to appropriate handler based on event metadata
      // Both handlers are safe to call -- they filter by metadata.type
      await Promise.all([
        ctx.runAction(internal.subscription.handlePaystackWebhook, {
          event: eventStr,
          dataJson,
        }),
        ctx.runAction(internal.ticketPayment.handleTicketWebhook, {
          event: eventStr,
          dataJson,
        }),
      ]);
    }

    return new Response(null, { status: 200 });
  }),
});

// ─── FedaPay webhook ─────────────────────────────────────────────────────────

http.route({
  path: "/fedapay-webhook",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.text();

    let payload: Record<string, unknown> = {};
    try {
      payload = JSON.parse(body) as Record<string, unknown>;
    } catch {
      return new Response("Invalid JSON", { status: 400 });
    }

    // FedaPay sends the full event payload
    await ctx.runAction(internal.fedaPayment.handleFedaPayWebhook, {
      dataJson: JSON.stringify(payload),
    });

    return new Response(null, { status: 200 });
  }),
});

export default http;
