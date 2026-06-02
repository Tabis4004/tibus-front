import { v } from "convex/values";
import { paginationOptsValidator } from "convex/server";
import { query, mutation, internalMutation } from "./_generated/server";
import { internal } from "./_generated/api.js";
import { ConvexError } from "convex/values";

// ─── Queries ─────────────────────────────────────────────────────────────────

export const list = query({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    return await ctx.db
      .query("notifications")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .paginate(args.paginationOpts);
  },
});

export const unreadCount = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return 0;

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return 0;

    const unread = await ctx.db
      .query("notifications")
      .withIndex("by_user_and_read", (q) => q.eq("userId", user._id).eq("isRead", false))
      .collect();

    return unread.length;
  },
});

// ─── Mutations ───────────────────────────────────────────────────────────────

export const markAsRead = mutation({
  args: { notificationId: v.id("notifications") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const notification = await ctx.db.get(args.notificationId);
    if (!notification) return;

    await ctx.db.patch(args.notificationId, { isRead: true });
  },
});

export const markAllAsRead = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return;

    const unread = await ctx.db
      .query("notifications")
      .withIndex("by_user_and_read", (q) =>
        q.eq("userId", user._id).eq("isRead", false)
      )
      .collect();

    for (const n of unread) {
      await ctx.db.patch(n._id, { isRead: true });
    }
  },
});

export const deleteNotification = mutation({
  args: { notificationId: v.id("notifications") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const notification = await ctx.db.get(args.notificationId);
    if (!notification) throw new ConvexError({ message: "Notification not found", code: "NOT_FOUND" });

    await ctx.db.delete(args.notificationId);
  },
});

// ─── Internal: generic create notification ──────────────────────────────────

export const createNotification = internalMutation({
  args: {
    userId: v.id("users"),
    type: v.string(),
    title: v.string(),
    message: v.string(),
    relatedBookingId: v.optional(v.id("bookings")),
    relatedTripId: v.optional(v.id("trips")),
  },
  handler: async (ctx, args) => {
    await ctx.db.insert("notifications", {
      userId: args.userId,
      type: args.type,
      title: args.title,
      message: args.message,
      isRead: false,
      relatedBookingId: args.relatedBookingId,
      relatedTripId: args.relatedTripId,
    });
  },
});

// ─── Internal: booking confirmed ────────────────────────────────────────────

export const notifyBookingConfirmed = internalMutation({
  args: {
    bookingId: v.id("bookings"),
    travelerId: v.id("users"),
    bookingReference: v.string(),
    tripId: v.id("trips"),
  },
  handler: async (ctx, args): Promise<void> => {
    await ctx.db.insert("notifications", {
      userId: args.travelerId,
      type: "booking_confirmed",
      title: "Booking Confirmed",
      message: `Your booking ${args.bookingReference} has been created successfully.`,
      isRead: false,
      relatedBookingId: args.bookingId,
      relatedTripId: args.tripId,
    });

    // Send push notification to traveler
    const traveler = await ctx.db.get(args.travelerId);
    if (traveler) {
      const visitorId = traveler.tokenIdentifier.split("|")[1];
      await ctx.scheduler.runAfter(0, internal.pushNotifications.sendNotification, {
        visitorIds: [visitorId],
        title: "Booking Confirmed",
        body: `Your booking ${args.bookingReference} has been created.`,
      });
    }
  },
});

// ─── Internal: new booking (notify owner + sellers) ─────────────────────────

export const notifyNewBooking = internalMutation({
  args: {
    bookingId: v.id("bookings"),
    tripId: v.id("trips"),
    passengerName: v.string(),
    companyId: v.id("companies"),
  },
  handler: async (ctx, args): Promise<void> => {
    const company = await ctx.db.get(args.companyId);
    if (!company) return;

    // Notify company owner
    await ctx.db.insert("notifications", {
      userId: company.ownerId,
      type: "new_booking",
      title: "New Booking",
      message: `${args.passengerName} booked a seat on your trip.`,
      isRead: false,
      relatedBookingId: args.bookingId,
      relatedTripId: args.tripId,
    });

    // Push to owner
    const owner = await ctx.db.get(company.ownerId);
    if (owner) {
      const visitorId = owner.tokenIdentifier.split("|")[1];
      await ctx.scheduler.runAfter(0, internal.pushNotifications.sendNotification, {
        visitorIds: [visitorId],
        title: "New Booking",
        body: `${args.passengerName} booked a seat on your trip.`,
      });
    }

    // Notify sellers of the same company
    const sellers = await ctx.db
      .query("users")
      .withIndex("by_role", (q) => q.eq("role", "seller"))
      .collect();

    const companySellers = sellers.filter((s) => s.companyId === args.companyId);
    for (const seller of companySellers) {
      await ctx.db.insert("notifications", {
        userId: seller._id,
        type: "new_booking",
        title: "New Booking",
        message: `${args.passengerName} booked a seat.`,
        isRead: false,
        relatedBookingId: args.bookingId,
        relatedTripId: args.tripId,
      });
    }
  },
});

// ─── Internal: booking cancelled ────────────────────────────────────────────

export const notifyBookingCancelled = internalMutation({
  args: {
    bookingId: v.id("bookings"),
    travelerId: v.id("users"),
    bookingReference: v.string(),
  },
  handler: async (ctx, args): Promise<void> => {
    await ctx.db.insert("notifications", {
      userId: args.travelerId,
      type: "booking_cancelled",
      title: "Booking Cancelled",
      message: `Your booking ${args.bookingReference} has been cancelled.`,
      isRead: false,
      relatedBookingId: args.bookingId,
    });

    // Push to traveler
    const traveler = await ctx.db.get(args.travelerId);
    if (traveler) {
      const visitorId = traveler.tokenIdentifier.split("|")[1];
      await ctx.scheduler.runAfter(0, internal.pushNotifications.sendNotification, {
        visitorIds: [visitorId],
        title: "Booking Cancelled",
        body: `Your booking ${args.bookingReference} has been cancelled.`,
      });
    }

    // Notify company owner
    const booking = await ctx.db.get(args.bookingId);
    if (booking) {
      const trip = await ctx.db.get(booking.tripId);
      if (trip) {
        const company = await ctx.db.get(trip.companyId);
        if (company) {
          await ctx.db.insert("notifications", {
            userId: company.ownerId,
            type: "booking_cancelled",
            title: "Booking Cancelled",
            message: `Booking ${args.bookingReference} has been cancelled by the traveler.`,
            isRead: false,
            relatedBookingId: args.bookingId,
          });
        }
      }
    }
  },
});

// ─── Internal: trip full (notify owner) ─────────────────────────────────────

export const notifyTripFull = internalMutation({
  args: {
    tripId: v.id("trips"),
    companyId: v.id("companies"),
  },
  handler: async (ctx, args): Promise<void> => {
    const company = await ctx.db.get(args.companyId);
    if (!company) return;

    const trip = await ctx.db.get(args.tripId);
    if (!trip) return;

    const route = await ctx.db.get(trip.routeId);
    const origin = route ? await ctx.db.get(route.originStationId) : null;
    const destination = route ? await ctx.db.get(route.destinationStationId) : null;
    const routeLabel = origin && destination
      ? `${origin.name} → ${destination.name}`
      : "a trip";

    await ctx.db.insert("notifications", {
      userId: company.ownerId,
      type: "new_booking",
      title: "Trip Full",
      message: `All seats are booked for ${routeLabel}.`,
      isRead: false,
      relatedTripId: args.tripId,
    });

    // Push to owner
    const owner = await ctx.db.get(company.ownerId);
    if (owner) {
      const visitorId = owner.tokenIdentifier.split("|")[1];
      await ctx.scheduler.runAfter(0, internal.pushNotifications.sendNotification, {
        visitorIds: [visitorId],
        title: "Trip Full",
        body: `All seats are booked for ${routeLabel}.`,
      });
    }
  },
});

// ─── Internal: seller assigned (notify the seller) ──────────────────────────

export const notifySellerAssigned = internalMutation({
  args: {
    sellerId: v.id("users"),
    companyId: v.id("companies"),
  },
  handler: async (ctx, args): Promise<void> => {
    const company = await ctx.db.get(args.companyId);
    if (!company) return;

    await ctx.db.insert("notifications", {
      userId: args.sellerId,
      type: "new_booking",
      title: "Seller Assignment",
      message: `You have been assigned as a seller for ${company.name}.`,
      isRead: false,
    });

    // Push to seller
    const seller = await ctx.db.get(args.sellerId);
    if (seller) {
      const visitorId = seller.tokenIdentifier.split("|")[1];
      await ctx.scheduler.runAfter(0, internal.pushNotifications.sendNotification, {
        visitorIds: [visitorId],
        title: "Seller Assignment",
        body: `You have been assigned as a seller for ${company.name}.`,
      });
    }
  },
});

// ─── Internal: trip departure reminder ──────────────────────────────────────

export const notifyTripDepartureReminder = internalMutation({
  args: {
    tripId: v.id("trips"),
  },
  handler: async (ctx, args): Promise<void> => {
    const trip = await ctx.db.get(args.tripId);
    if (!trip || trip.status === "cancelled") return;

    const route = await ctx.db.get(trip.routeId);
    const origin = route ? await ctx.db.get(route.originStationId) : null;
    const destination = route ? await ctx.db.get(route.destinationStationId) : null;
    const routeLabel = origin && destination
      ? `${origin.name} → ${destination.name}`
      : "your trip";

    // Find all confirmed bookings for this trip
    const bookings = await ctx.db
      .query("bookings")
      .withIndex("by_trip", (q) => q.eq("tripId", args.tripId))
      .collect();

    const activeBookings = bookings.filter(
      (b) => b.status === "confirmed" || b.status === "pending_payment"
    );

    for (const booking of activeBookings) {
      await ctx.db.insert("notifications", {
        userId: booking.travelerId,
        type: "trip_reminder",
        title: "Trip Departing Soon",
        message: `Your trip ${routeLabel} departs in 1 hour.`,
        isRead: false,
        relatedBookingId: booking._id,
        relatedTripId: args.tripId,
      });

      // Push notification
      const traveler = await ctx.db.get(booking.travelerId);
      if (traveler) {
        const visitorId = traveler.tokenIdentifier.split("|")[1];
        await ctx.scheduler.runAfter(0, internal.pushNotifications.sendNotification, {
          visitorIds: [visitorId],
          title: "Trip Departing Soon",
          body: `Your trip ${routeLabel} departs in 1 hour.`,
        });
      }
    }
  },
});

// ─── Internal: trip cancelled (notify all affected travelers) ────────────────

export const notifyTripCancelled = internalMutation({
  args: {
    tripId: v.id("trips"),
  },
  handler: async (ctx, args): Promise<void> => {
    const trip = await ctx.db.get(args.tripId);
    if (!trip) return;

    const route = await ctx.db.get(trip.routeId);
    const origin = route ? await ctx.db.get(route.originStationId) : null;
    const destination = route ? await ctx.db.get(route.destinationStationId) : null;

    const routeLabel = origin && destination
      ? `${origin.name} → ${destination.name}`
      : "your trip";

    // Find all active bookings for this trip
    const bookings = await ctx.db
      .query("bookings")
      .withIndex("by_trip", (q) => q.eq("tripId", args.tripId))
      .collect();

    const activeBookings = bookings.filter(
      (b) => b.status === "confirmed" || b.status === "pending_payment"
    );

    // Notify each traveler
    for (const booking of activeBookings) {
      await ctx.db.insert("notifications", {
        userId: booking.travelerId,
        type: "trip_change",
        title: "Trip Cancelled",
        message: `Your trip ${routeLabel} has been cancelled by the company.`,
        isRead: false,
        relatedBookingId: booking._id,
        relatedTripId: args.tripId,
      });

      // Push notification
      const traveler = await ctx.db.get(booking.travelerId);
      if (traveler) {
        const visitorId = traveler.tokenIdentifier.split("|")[1];
        await ctx.scheduler.runAfter(0, internal.pushNotifications.sendNotification, {
          visitorIds: [visitorId],
          title: "Trip Cancelled",
          body: `Your trip ${routeLabel} has been cancelled.`,
        });
      }
    }
  },
});
