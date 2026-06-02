import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { resolveStationLocation } from "./stationHelpers.ts";
import { recordCommission } from "./commissionHelpers.ts";
import { internal } from "./_generated/api.js";

function generateRef(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let ref = "TB-";
  for (let i = 0; i < 8; i++) {
    ref += chars[Math.floor(Math.random() * chars.length)];
  }
  return ref;
}

// ─── Seat availability ────────────────────────────────────────────────────

export const getOccupiedSeats = query({
  args: { tripId: v.id("trips") },
  handler: async (ctx, args) => {
    const bookings = await ctx.db
      .query("bookings")
      .withIndex("by_trip", (q) => q.eq("tripId", args.tripId))
      .collect();

    // Return occupied seats (exclude cancelled bookings)
    return bookings
      .filter((b) => b.status !== "cancelled" && b.seatNumber)
      .map((b) => b.seatNumber as string);
  },
});

// ─── Public trip search ────────────────────────────────────────────────────

export const searchTrips = query({
  args: {
    originCity: v.optional(v.string()),
    destinationCity: v.optional(v.string()),
    departureDate: v.optional(v.string()), // "YYYY-MM-DD"
    companyId: v.optional(v.id("companies")),
    countryId: v.optional(v.id("countries")),
  },
  handler: async (ctx, args) => {
    // Get all scheduled trips (public query - no auth required)
    const now = new Date().toISOString();
    const allTrips = await ctx.db
      .query("trips")
      .withIndex("by_departure", (q) => q.gte("departureTime", now))
      .order("asc")
      .take(200);

    const scheduled = allTrips.filter((t) => t.status === "scheduled");

    const results = await Promise.all(
      scheduled.map(async (t) => {
        // Filter by companyId
        if (args.companyId && t.companyId !== args.companyId) return null;

        // Filter by date
        if (args.departureDate) {
          if (!t.departureTime.startsWith(args.departureDate)) return null;
        }

        const route = await ctx.db.get(t.routeId);
        if (!route || !route.isActive) return null;

        const bus = await ctx.db.get(t.busId);
        const origin = await ctx.db.get(route.originStationId);
        const destination = await ctx.db.get(route.destinationStationId);
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);
        const company = await ctx.db.get(t.companyId);

        // Filter by country — check if either origin or destination city is in that country
        if (args.countryId) {
          const originInCountry = origin?.cityId
            ? (await ctx.db.get(origin.cityId))?.countryId === args.countryId
            : false;
          const destInCountry = destination?.cityId
            ? (await ctx.db.get(destination.cityId))?.countryId === args.countryId
            : false;
          if (!originInCountry && !destInCountry) return null;
        }

        // Filter by city name
        if (args.originCity && originLoc?.city.toLowerCase() !== args.originCity.toLowerCase()) return null;
        if (args.destinationCity && destLoc?.city.toLowerCase() !== args.destinationCity.toLowerCase()) return null;

        return {
          ...t,
          route,
          bus,
          origin,
          destination,
          originLoc,
          destLoc,
          company,
        };
      })
    );

    return results.filter((r): r is NonNullable<typeof r> => r !== null);
  },
});

export const getTripDetails = query({
  args: { tripId: v.id("trips") },
  handler: async (ctx, args) => {
    const trip = await ctx.db.get(args.tripId);
    if (!trip) return null;

    const route = await ctx.db.get(trip.routeId);
    const bus = await ctx.db.get(trip.busId);
    const origin = route ? await ctx.db.get(route.originStationId) : null;
    const destination = route ? await ctx.db.get(route.destinationStationId) : null;
    const originLoc = await resolveStationLocation(ctx, origin);
    const destLoc = await resolveStationLocation(ctx, destination);
    const company = await ctx.db.get(trip.companyId);

    return { ...trip, route, bus, origin, destination, originLoc, destLoc, company };
  },
});

// ─── Booking mutations ─────────────────────────────────────────────────────

export const createBooking = mutation({
  args: {
    tripId: v.id("trips"),
    passengerName: v.string(),
    passengerPhone: v.optional(v.string()),
    seatNumber: v.optional(v.string()),
    promoCodeId: v.optional(v.id("promoCodes")),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    const trip = await ctx.db.get(args.tripId);
    if (!trip) throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });
    if (trip.status !== "scheduled") throw new ConvexError({ message: "Trip is not available for booking", code: "BAD_REQUEST" });
    if (trip.seatsAvailable <= 0) throw new ConvexError({ message: "No seats available", code: "BAD_REQUEST" });

    // Validate seat is not already occupied
    if (args.seatNumber) {
      const seatTaken = await ctx.db
        .query("bookings")
        .withIndex("by_trip", (q) => q.eq("tripId", args.tripId))
        .filter((q) =>
          q.and(
            q.eq(q.field("seatNumber"), args.seatNumber),
            q.neq(q.field("status"), "cancelled")
          )
        )
        .first();
      if (seatTaken) throw new ConvexError({ message: "This seat is already taken", code: "CONFLICT" });
    }

    // Check for duplicate booking
    const existing = await ctx.db
      .query("bookings")
      .withIndex("by_traveler", (q) => q.eq("travelerId", user._id))
      .filter((q) => q.eq(q.field("tripId"), args.tripId))
      .filter((q) =>
        q.or(
          q.eq(q.field("status"), "confirmed"),
          q.eq(q.field("status"), "pending_payment")
        )
      )
      .first();
    if (existing) throw new ConvexError({ message: "You already have a booking for this trip", code: "CONFLICT" });

    // Apply promo code discount
    let totalPrice = trip.priceAmount;
    if (args.promoCodeId) {
      const promo = await ctx.db.get(args.promoCodeId);
      if (promo && promo.isActive) {
        const now = new Date().toISOString();
        if (now >= promo.validFrom && now <= promo.validUntil) {
          if (!promo.maxUsage || promo.usageCount < promo.maxUsage) {
            if (!promo.routeId || promo.routeId === trip.routeId) {
              let discount = 0;
              if (promo.discountType === "percentage") {
                discount = Math.round((trip.priceAmount * promo.discountValue) / 100);
              } else {
                discount = promo.discountValue;
              }
              totalPrice = Math.max(0, trip.priceAmount - Math.min(discount, trip.priceAmount));
              // Increment usage
              await ctx.db.patch(args.promoCodeId, { usageCount: promo.usageCount + 1 });
            }
          }
        }
      }
    }

    const bookingId = await ctx.db.insert("bookings", {
      tripId: args.tripId,
      travelerId: user._id,
      passengerName: args.passengerName,
      passengerPhone: args.passengerPhone,
      seatNumber: args.seatNumber,
      status: "pending_payment",
      totalPrice,
      currency: trip.currency,
      bookingReference: generateRef(),
      paymentStatus: "pending",
    });

    // Decrease seats
    const newSeatsAvailable = trip.seatsAvailable - 1;
    await ctx.db.patch(args.tripId, { seatsAvailable: newSeatsAvailable });

    // Record commission if applicable
    await recordCommission(ctx, bookingId, trip.companyId, totalPrice, trip.currency);

    // Notify owner and traveler
    const newBooking = await ctx.db.get(bookingId);
    await ctx.scheduler.runAfter(0, internal.notifications.notifyBookingConfirmed, {
      bookingId,
      travelerId: user._id,
      bookingReference: newBooking?.bookingReference ?? "N/A",
      tripId: args.tripId,
    });

    await ctx.scheduler.runAfter(0, internal.notifications.notifyNewBooking, {
      bookingId,
      tripId: args.tripId,
      passengerName: args.passengerName,
      companyId: trip.companyId,
    });

    // Notify owner if trip is now full
    if (newSeatsAvailable === 0) {
      await ctx.scheduler.runAfter(0, internal.notifications.notifyTripFull, {
        tripId: args.tripId,
        companyId: trip.companyId,
      });
    }

    return bookingId;
  },
});

export const cancelBooking = mutation({
  args: { bookingId: v.id("bookings") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new ConvexError({ message: "Booking not found", code: "NOT_FOUND" });
    if (booking.travelerId !== user._id)
      throw new ConvexError({ message: "Not your booking", code: "FORBIDDEN" });
    if (booking.status === "cancelled")
      throw new ConvexError({ message: "Booking already cancelled", code: "BAD_REQUEST" });
    if (booking.status === "collected")
      throw new ConvexError({ message: "Cannot cancel a collected ticket", code: "BAD_REQUEST" });

    await ctx.db.patch(args.bookingId, { status: "cancelled" });

    // Restore seat
    const trip = await ctx.db.get(booking.tripId);
    if (trip) {
      await ctx.db.patch(booking.tripId, { seatsAvailable: trip.seatsAvailable + 1 });
    }

    // Notify traveler about cancellation
    await ctx.scheduler.runAfter(0, internal.notifications.notifyBookingCancelled, {
      bookingId: args.bookingId,
      travelerId: user._id,
      bookingReference: booking.bookingReference,
    });
  },
});

// ─── Traveler queries ──────────────────────────────────────────────────────

export const listMyBookings = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return [];

    const bookings = await ctx.db
      .query("bookings")
      .withIndex("by_traveler", (q) => q.eq("travelerId", user._id))
      .order("desc")
      .collect();

    return await Promise.all(
      bookings.map(async (b) => {
        const trip = await ctx.db.get(b.tripId);
        const route = trip ? await ctx.db.get(trip.routeId) : null;
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);
        const company = trip ? await ctx.db.get(trip.companyId) : null;
        return { ...b, trip, origin, destination, originLoc, destLoc, company };
      })
    );
  },
});

// ─── Public ticket verification (for QR code scan) ────────────────────────

export const verifyByReference = query({
  args: { reference: v.string() },
  handler: async (ctx, args) => {
    const booking = await ctx.db
      .query("bookings")
      .withIndex("by_reference", (q) => q.eq("bookingReference", args.reference))
      .unique();

    if (!booking) return null;

    const trip = await ctx.db.get(booking.tripId);
    const route = trip ? await ctx.db.get(trip.routeId) : null;
    const bus = trip ? await ctx.db.get(trip.busId) : null;
    const origin = route ? await ctx.db.get(route.originStationId) : null;
    const destination = route ? await ctx.db.get(route.destinationStationId) : null;
    const originLoc = await resolveStationLocation(ctx, origin);
    const destLoc = await resolveStationLocation(ctx, destination);
    const company = trip ? await ctx.db.get(trip.companyId) : null;

    return {
      bookingReference: booking.bookingReference,
      passengerName: booking.passengerName,
      passengerPhone: booking.passengerPhone,
      seatNumber: booking.seatNumber,
      status: booking.status,
      paymentStatus: booking.paymentStatus,
      totalPrice: booking.totalPrice,
      currency: booking.currency,
      createdAt: booking._creationTime,
      trip: trip
        ? {
            departureTime: trip.departureTime,
            arrivalTime: trip.arrivalTime,
          }
        : null,
      bus: bus
        ? { name: bus.name, plateNumber: bus.plateNumber, busType: bus.busType }
        : null,
      origin: origin ? { name: origin.name, address: origin.address } : null,
      destination: destination
        ? { name: destination.name, address: destination.address }
        : null,
      originLoc,
      destLoc,
      company: company ? { name: company.name } : null,
    };
  },
});

export const getBooking = query({
  args: { bookingId: v.id("bookings") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return null;

    const booking = await ctx.db.get(args.bookingId);
    if (!booking || booking.travelerId !== user._id) return null;

    const trip = await ctx.db.get(booking.tripId);
    const route = trip ? await ctx.db.get(trip.routeId) : null;
    const bus = trip ? await ctx.db.get(trip.busId) : null;
    const origin = route ? await ctx.db.get(route.originStationId) : null;
    const destination = route ? await ctx.db.get(route.destinationStationId) : null;
    const originLoc = await resolveStationLocation(ctx, origin);
    const destLoc = await resolveStationLocation(ctx, destination);
    const company = trip ? await ctx.db.get(trip.companyId) : null;

    return { ...booking, trip, route, bus, origin, destination, originLoc, destLoc, company };
  },
});
