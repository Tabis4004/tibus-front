"use node";

import { action, internalAction } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { internal } from "./_generated/api";

// FedaPay API — sandbox: https://sandbox-api.fedapay.com, live: https://api.fedapay.com
const FEDAPAY_BASE = "https://api.fedapay.com";

function fedaPayHeaders() {
  const secretKey = process.env.FEDAPAY_SECRET_KEY;
  if (!secretKey)
    throw new ConvexError({
      message: "FedaPay API key not configured",
      code: "EXTERNAL_SERVICE_ERROR",
    });
  return {
    Authorization: `Bearer ${secretKey}`,
    "Content-Type": "application/json",
  };
}

/**
 * Initialize a FedaPay payment for a booking.
 * 1. Create a transaction
 * 2. Generate a payment token/checkout URL
 * 3. Redirect user to FedaPay checkout
 */
export const initializePayment = action({
  args: {
    bookingId: v.id("bookings"),
    successUrl: v.string(),
    errorUrl: v.string(),
  },
  handler: async (ctx, args): Promise<{ checkoutUrl: string; reference: string }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity)
      throw new ConvexError({
        message: "Not authenticated",
        code: "UNAUTHENTICATED",
      });

    // Fetch booking details
    const booking = await ctx.runQuery(
      internal.ticketPaymentHelpers.getBookingForPayment,
      { bookingId: args.bookingId, tokenIdentifier: identity.tokenIdentifier },
    );

    if (!booking)
      throw new ConvexError({
        message: "Booking not found or not yours",
        code: "NOT_FOUND",
      });

    if (booking.status !== "pending_payment")
      throw new ConvexError({
        message: "Booking is not awaiting payment",
        code: "BAD_REQUEST",
      });

    const customerName = booking.passengerName;
    const customerEmail = identity.email ?? "customer@tibus.app";
    const customerPhone = booking.passengerPhone ?? "";

    // Split name into first/last
    const nameParts = customerName.trim().split(/\s+/);
    const firstname = nameParts[0] ?? customerName;
    const lastname = nameParts.length > 1 ? nameParts.slice(1).join(" ") : customerName;

    // Step 1: Create FedaPay transaction
    const txnBody = {
      description: `Ticket ${booking.bookingReference}`,
      amount: booking.totalPrice,
      currency: { iso: "XOF" },
      callback_url: args.successUrl,
      customer: {
        firstname,
        lastname,
        email: customerEmail,
        phone_number: { number: customerPhone, country: "ci" },
      },
      custom_metadata: {
        bookingId: booking._id,
        bookingReference: booking.bookingReference,
        tripId: booking.tripId,
        type: "ticket_payment",
      },
    };

    console.log("FedaPay create transaction request:", JSON.stringify(txnBody));

    const txnRes = await fetch(`${FEDAPAY_BASE}/v1/transactions`, {
      method: "POST",
      headers: fedaPayHeaders(),
      body: JSON.stringify(txnBody),
    });

    const txnText = await txnRes.text();
    console.log("FedaPay create transaction response status:", txnRes.status);
    console.log("FedaPay create transaction response:", txnText);

    let txnJson: Record<string, unknown>;
    try {
      txnJson = JSON.parse(txnText) as Record<string, unknown>;
    } catch {
      throw new ConvexError({
        message: `FedaPay returned invalid response: ${txnText.slice(0, 200)}`,
        code: "EXTERNAL_SERVICE_ERROR",
      });
    }

    // FedaPay returns keys like "v1/transaction" (with slash, not nested)
    type TxnData = { id?: number; reference?: string; status?: string };
    const txnData: TxnData =
      (txnJson["v1/transaction"] as TxnData) ??
      (txnJson as { v1?: { transaction?: TxnData } }).v1?.transaction ??
      (txnJson as TxnData);

    const transactionId = txnData.id;
    const reference = txnData.reference;

    if (!transactionId || !reference)
      throw new ConvexError({
        message: `Failed to create FedaPay transaction: ${txnText.slice(0, 300)}`,
        code: "EXTERNAL_SERVICE_ERROR",
      });

    // Step 2: Generate payment token/checkout URL
    const tokenRes = await fetch(
      `${FEDAPAY_BASE}/v1/transactions/${transactionId}/token`,
      {
        method: "POST",
        headers: fedaPayHeaders(),
      },
    );

    const tokenText = await tokenRes.text();
    console.log("FedaPay token response status:", tokenRes.status);
    console.log("FedaPay token response:", tokenText);

    let tokenJson: Record<string, unknown>;
    try {
      tokenJson = JSON.parse(tokenText) as Record<string, unknown>;
    } catch {
      throw new ConvexError({
        message: `FedaPay token returned invalid response: ${tokenText.slice(0, 200)}`,
        code: "EXTERNAL_SERVICE_ERROR",
      });
    }

    const checkoutUrl = (tokenJson.url as string | undefined) ??
      (tokenJson.token as string | undefined);

    if (!checkoutUrl)
      throw new ConvexError({
        message: `No checkout URL returned by FedaPay: ${tokenText.slice(0, 300)}`,
        code: "EXTERNAL_SERVICE_ERROR",
      });

    // Save reference to booking
    await ctx.runMutation(
      internal.ticketPaymentHelpers.setPaystackReference,
      { bookingId: args.bookingId, reference },
    );

    return { checkoutUrl, reference };
  },
});

/**
 * Verify a FedaPay payment after redirect.
 * Accepts either transactionId (from FedaPay redirect URL ?id=...) or reference.
 */
export const verifyPayment = action({
  args: {
    transactionId: v.optional(v.string()),
    reference: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<{ success: boolean; bookingId?: string }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity)
      throw new ConvexError({
        message: "Not authenticated",
        code: "UNAUTHENTICATED",
      });

    type TxnData = {
      id?: number;
      reference?: string;
      status?: string;
      custom_metadata?: Record<string, string>;
    };

    let txn: TxnData | null = null;

    // Prefer fetching by transaction ID (direct lookup, not deprecated)
    if (args.transactionId) {
      const res = await fetch(
        `${FEDAPAY_BASE}/v1/transactions/${args.transactionId}`,
        { headers: fedaPayHeaders() },
      );
      const text = await res.text();
      console.log("FedaPay verify by ID response:", text);

      try {
        const json = JSON.parse(text) as Record<string, unknown>;
        txn =
          (json["v1/transaction"] as TxnData | undefined) ??
          (json as TxnData);
      } catch {
        console.log("FedaPay verify parse error");
      }
    }

    // Fallback: search by reference using the new search endpoint
    if (!txn && args.reference) {
      const res = await fetch(
        `${FEDAPAY_BASE}/v1/transactions/search?reference=${encodeURIComponent(args.reference)}`,
        { headers: fedaPayHeaders() },
      );
      const text = await res.text();
      console.log("FedaPay verify by reference response:", text);

      try {
        const json = JSON.parse(text) as Record<string, unknown>;
        const txnList =
          (json["v1/transactions"] as TxnData[] | undefined) ??
          (json["v1/transaction"] as TxnData | TxnData[] | undefined) ??
          (json as { items?: TxnData[] }).items ??
          (json as { data?: TxnData[] }).data;

        const transactions: TxnData[] = Array.isArray(txnList)
          ? txnList
          : txnList
            ? [txnList]
            : [];

        txn = transactions.find((t) => t.reference === args.reference) ?? null;
      } catch {
        console.log("FedaPay verify search parse error");
      }
    }

    if (!txn || (txn.status !== "approved" && txn.status !== "transferred")) {
      return { success: false };
    }

    const bookingId = txn.custom_metadata?.bookingId;
    const reference = txn.reference ?? args.reference ?? "";
    if (!bookingId) return { success: false };

    // Confirm the booking
    await ctx.runMutation(
      internal.ticketPaymentHelpers.confirmBookingPayment,
      {
        bookingId,
        tokenIdentifier: identity.tokenIdentifier,
        reference,
      },
    );

    return { success: true, bookingId };
  },
});

/**
 * Handle FedaPay webhook (called from http.ts).
 * FedaPay webhook format:
 *   { name: "transaction.approved", object: "transaction", entity: { ...txn data }, account: {...} }
 * The actual transaction data is in the `entity` field (not `object`).
 */
export const handleFedaPayWebhook = internalAction({
  args: { dataJson: v.string() },
  handler: async (ctx, args): Promise<void> => {
    console.log("FedaPay webhook received:", args.dataJson);

    const payload = JSON.parse(args.dataJson) as {
      name?: string;
      object?: string;
      entity?: {
        id?: number;
        reference?: string;
        status?: string;
        custom_metadata?: Record<string, string>;
      };
    };

    // Only process transaction events
    if (payload.object !== "transaction") return;

    // The transaction data is in the `entity` field
    const txn = payload.entity;
    if (!txn) return;

    // Only process approved/transferred transactions
    if (txn.status !== "approved" && txn.status !== "transferred") return;

    const bookingId = txn.custom_metadata?.bookingId;
    const reference = txn.reference;
    if (!bookingId || !reference) return;
    if (txn.custom_metadata?.type !== "ticket_payment") return;

    await ctx.runMutation(
      internal.ticketPaymentHelpers.confirmBookingPaymentByWebhook,
      { bookingId, reference },
    );
  },
});
