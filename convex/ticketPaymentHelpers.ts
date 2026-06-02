import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";
import type { Id } from "./_generated/dataModel.d.ts";

// ─── Internal V8 helpers for ticket payment ──────────────────────────────────

export const getBookingForPayment = internalQuery({
  args: {
    bookingId: v.id("bookings"),
    tokenIdentifier: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", args.tokenIdentifier))
      .unique();
    if (!user) return null;

    const booking = await ctx.db.get(args.bookingId);
    if (!booking) return null;
    if (booking.travelerId !== user._id) return null;

    return booking;
  },
});

export const setPaystackReference = internalMutation({
  args: {
    bookingId: v.id("bookings"),
    reference: v.string(),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.bookingId, {
      paystackReference: args.reference,
    });
  },
});

export const confirmBookingPayment = internalMutation({
  args: {
    bookingId: v.string(),
    tokenIdentifier: v.string(),
    reference: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", args.tokenIdentifier))
      .unique();
    if (!user) return;

    const booking = await ctx.db.get(args.bookingId as Id<"bookings">);
    if (!booking) return;
    if (booking.travelerId !== user._id) return;

    // Only confirm if still pending
    if (booking.status === "pending_payment") {
      await ctx.db.patch(args.bookingId as Id<"bookings">, {
        status: "confirmed",
        paymentStatus: "paid",
        paystackReference: args.reference,
      });
    }
  },
});

export const confirmBookingPaymentByWebhook = internalMutation({
  args: {
    bookingId: v.string(),
    reference: v.string(),
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId as Id<"bookings">);
    if (!booking) return;

    // Only confirm if still pending
    if (booking.status === "pending_payment") {
      await ctx.db.patch(args.bookingId as Id<"bookings">, {
        status: "confirmed",
        paymentStatus: "paid",
        paystackReference: args.reference,
      });
    }
  },
});
