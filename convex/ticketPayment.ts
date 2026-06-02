"use node";

import { action, internalAction } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { internal } from "./_generated/api";

function paystackHeaders() {
  const key = process.env.PAYSTACK_SECRET_KEY;
  if (!key)
    throw new ConvexError({
      message: "PAYSTACK_SECRET_KEY not configured",
      code: "EXTERNAL_SERVICE_ERROR",
    });
  return {
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
  };
}

/**
 * Initialize a Paystack payment for a booking.
 * The booking must already exist with status "pending_payment".
 */
export const initializeTicketPayment = action({
  args: {
    bookingId: v.id("bookings"),
    callbackUrl: v.string(),
  },
  handler: async (ctx, args): Promise<{ url: string; reference: string }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity)
      throw new ConvexError({
        message: "Not authenticated",
        code: "UNAUTHENTICATED",
      });

    // Fetch booking details via internal query
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

    const email = identity.email ?? "customer@tibus.app";

    // Initialize Paystack transaction
    const res = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: paystackHeaders(),
      body: JSON.stringify({
        email,
        amount: booking.totalPrice * 100, // Paystack expects amount in kobo/lowest unit
        currency: booking.currency,
        callback_url: args.callbackUrl,
        metadata: {
          bookingId: booking._id,
          bookingReference: booking.bookingReference,
          tripId: booking.tripId,
          type: "ticket_payment",
          custom_fields: [
            {
              display_name: "Booking Reference",
              variable_name: "booking_ref",
              value: booking.bookingReference,
            },
            {
              display_name: "Passenger",
              variable_name: "passenger",
              value: booking.passengerName,
            },
          ],
        },
      }),
    });

    const json = (await res.json()) as {
      status: boolean;
      data: { authorization_url: string; reference: string };
      message?: string;
    };

    if (!json.status)
      throw new ConvexError({
        message: json.message ?? "Failed to initialize payment",
        code: "EXTERNAL_SERVICE_ERROR",
      });

    // Save reference to booking
    await ctx.runMutation(
      internal.ticketPaymentHelpers.setPaystackReference,
      { bookingId: args.bookingId, reference: json.data.reference },
    );

    return { url: json.data.authorization_url, reference: json.data.reference };
  },
});

/**
 * Verify a ticket payment after redirect back from Paystack.
 */
export const verifyTicketPayment = action({
  args: { reference: v.string() },
  handler: async (ctx, args): Promise<{ success: boolean; bookingId?: string }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity)
      throw new ConvexError({
        message: "Not authenticated",
        code: "UNAUTHENTICATED",
      });

    const res = await fetch(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(args.reference)}`,
      { headers: paystackHeaders() },
    );

    const json = (await res.json()) as {
      status: boolean;
      data: {
        status: string;
        metadata?: {
          bookingId?: string;
          type?: string;
        };
      };
    };

    if (!json.status || json.data.status !== "success") {
      return { success: false };
    }

    const bookingId = json.data.metadata?.bookingId;
    if (!bookingId) return { success: false };

    // Confirm the booking
    await ctx.runMutation(
      internal.ticketPaymentHelpers.confirmBookingPayment,
      {
        bookingId: bookingId as string,
        tokenIdentifier: identity.tokenIdentifier,
        reference: args.reference,
      },
    );

    return { success: true, bookingId };
  },
});

/**
 * Handle Paystack webhook for ticket payments (called from http.ts).
 */
export const handleTicketWebhook = internalAction({
  args: { event: v.string(), dataJson: v.string() },
  handler: async (ctx, args): Promise<void> => {
    if (args.event !== "charge.success") return;

    const payload = JSON.parse(args.dataJson) as {
      reference?: string;
      metadata?: {
        bookingId?: string;
        type?: string;
      };
    };

    // Only process ticket payments
    if (payload.metadata?.type !== "ticket_payment") return;

    const bookingId = payload.metadata.bookingId;
    const reference = payload.reference;
    if (!bookingId || !reference) return;

    await ctx.runMutation(
      internal.ticketPaymentHelpers.confirmBookingPaymentByWebhook,
      { bookingId, reference },
    );
  },
});
