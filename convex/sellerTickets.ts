import { mutation, query } from "./_generated/server";
import type { QueryCtx, MutationCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel.d.ts";
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

async function getSellerCompany(ctx: QueryCtx | MutationCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
  if (user.role !== "seller" && user.role !== "owner" && user.role !== "superadmin")
    throw new ConvexError({ message: "Sellers only", code: "FORBIDDEN" });

  // For owner/superadmin: use their own company; for seller: use assigned companyId
  let companyId = user.companyId;
  if (user.role === "owner" || user.role === "superadmin") {
    const company = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    companyId = company?._id;
  }

  if (!companyId) throw new ConvexError({ message: "No company assigned", code: "NOT_FOUND" });
  const company = await ctx.db.get(companyId);
  if (!company) throw new ConvexError({ message: "Company not found", code: "NOT_FOUND" });
  return { user, company };
}

// ─── Seller queries ────────────────────────────────────────────────────────

export const getSellerProfile = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user || (user.role !== "seller" && user.role !== "owner" && user.role !== "superadmin")) return null;

    let companyId = user.companyId;
    if (user.role === "owner" || user.role === "superadmin") {
      const company = await ctx.db
        .query("companies")
        .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
        .first();
      companyId = company?._id;
    }

    const company = companyId ? await ctx.db.get(companyId) : null;
    return { user, company };
  },
});

export const listSellerTrips = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getSellerCompany(ctx);

    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .filter((q) => q.eq(q.field("status"), "scheduled"))
      .order("asc")
      .collect();

    const now = new Date().toISOString();

    const enriched = await Promise.all(
      trips
        .filter((t) => t.departureTime > now)
        .map(async (t) => {
          const route = await ctx.db.get(t.routeId);
          const bus = await ctx.db.get(t.busId);
          const origin = route ? await ctx.db.get(route.originStationId) : null;
          const destination = route ? await ctx.db.get(route.destinationStationId) : null;
          const originLoc = await resolveStationLocation(ctx, origin);
          const destLoc = await resolveStationLocation(ctx, destination);
          return { ...t, route, bus, origin, destination, originLoc, destLoc };
        })
    );

    return enriched;
  },
});

export const listSellerSoldTickets = query({
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
      .withIndex("by_seller", (q) => q.eq("soldBySellerId", user._id))
      .order("desc")
      .collect();

    return await Promise.all(
      bookings.map(async (b) => {
        const trip = await ctx.db.get(b.tripId);
        const route = trip ? await ctx.db.get(trip.routeId) : null;
        const bus = trip ? await ctx.db.get(trip.busId) : null;
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);
        return { ...b, trip, bus, origin, destination, originLoc, destLoc };
      })
    );
  },
});

// ─── Traveler search & quick-create ──────────────────────────────────────────

export const searchTravelers = query({
  args: { searchTerm: v.string() },
  handler: async (ctx, args) => {
    const { company } = await getSellerCompany(ctx);
    const term = args.searchTerm.trim();
    if (term.length < 2) return [];

    // Check if it looks like a phone number (starts with + or digit)
    const isPhone = /^[+\d]/.test(term);

    let candidates: Array<{ _id: Id<"users">; name?: string; phone?: string; email?: string }> = [];

    if (isPhone) {
      // Search by phone across all users
      const allUsers = await ctx.db.query("users").collect();
      candidates = allUsers.filter(
        (u) => u.phone && u.phone.includes(term)
      );
    } else {
      // Use text search index on name
      const results = await ctx.db
        .query("users")
        .withSearchIndex("search_name", (q) => q.search("name", term))
        .take(20);
      candidates = results;
    }

    // Get company's traveler list
    const companyLinks = await ctx.db
      .query("companyTravelers")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    const linkedIds = new Set(companyLinks.map((l) => l.travelerId.toString()));

    // Return matches - prioritize linked travelers, then show all matches
    const linked = candidates.filter((c) => linkedIds.has(c._id.toString()));
    const unlinked = candidates.filter((c) => !linkedIds.has(c._id.toString()));

    const formatResult = (u: typeof candidates[number], isLinked: boolean) => ({
      _id: u._id,
      name: u.name ?? "",
      phone: u.phone ?? "",
      email: u.email ?? "",
      isCompanyClient: isLinked,
    });

    return [
      ...linked.map((u) => formatResult(u, true)),
      ...unlinked.map((u) => formatResult(u, false)),
    ].slice(0, 10);
  },
});

export const quickCreateTraveler = mutation({
  args: {
    name: v.string(),
    phone: v.string(),
  },
  handler: async (ctx, args) => {
    const { company } = await getSellerCompany(ctx);

    const trimName = args.name.trim();
    const trimPhone = args.phone.trim();
    if (!trimName) throw new ConvexError({ message: "Name is required", code: "BAD_REQUEST" });
    if (!trimPhone) throw new ConvexError({ message: "Phone is required", code: "BAD_REQUEST" });

    // Check if a user with this phone already exists
    const existing = await ctx.db
      .query("users")
      .withIndex("by_phone", (q) => q.eq("phone", trimPhone))
      .first();

    let travelerId: Id<"users">;

    if (existing) {
      travelerId = existing._id;
    } else {
      // Create a new user with traveler role, using company's country
      travelerId = await ctx.db.insert("users", {
        tokenIdentifier: `manual|${trimPhone}`,
        name: trimName,
        phone: trimPhone,
        role: "traveler",
        countryId: company.countryId,
        profileCompleted: false,
      });
    }

    // Link to company if not already linked
    const existingLink = await ctx.db
      .query("companyTravelers")
      .withIndex("by_company_and_traveler", (q) =>
        q.eq("companyId", company._id).eq("travelerId", travelerId)
      )
      .first();

    if (!existingLink) {
      await ctx.db.insert("companyTravelers", {
        companyId: company._id,
        travelerId,
      });
    }

    return { _id: travelerId, name: trimName, phone: trimPhone };
  },
});

// ─── Seller mutations ──────────────────────────────────────────────────────

export const sellerCreateBooking = mutation({
  args: {
    tripId: v.id("trips"),
    passengerName: v.string(),
    passengerPhone: v.optional(v.string()),
    travelerId: v.optional(v.id("users")),
    seatNumber: v.optional(v.string()),
    parcelCount: v.optional(v.number()),
    parcelWeight: v.optional(v.number()),
    parcelAmount: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { user, company } = await getSellerCompany(ctx);

    const trip = await ctx.db.get(args.tripId);
    if (!trip) throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });
    if (trip.companyId !== company._id)
      throw new ConvexError({ message: "Trip does not belong to your company", code: "FORBIDDEN" });
    if (trip.status !== "scheduled")
      throw new ConvexError({ message: "Trip is not available for booking", code: "BAD_REQUEST" });
    if (trip.seatsAvailable <= 0)
      throw new ConvexError({ message: "No seats available", code: "BAD_REQUEST" });

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

    // Use real traveler if provided, otherwise seller acts as proxy
    const actualTravelerId = args.travelerId ?? user._id;

    const parcelAmt = args.parcelAmount ?? 0;
    const totalPrice = trip.priceAmount + parcelAmt;

    const bookingId = await ctx.db.insert("bookings", {
      tripId: args.tripId,
      travelerId: actualTravelerId,
      soldBySellerId: user._id,
      passengerName: args.passengerName,
      passengerPhone: args.passengerPhone,
      seatNumber: args.seatNumber,
      status: "confirmed",
      totalPrice,
      currency: trip.currency,
      bookingReference: generateRef(),
      paymentStatus: "pending",
      parcelCount: args.parcelCount,
      parcelWeight: args.parcelWeight,
      parcelAmount: args.parcelAmount,
    });

    const newSeatsAvailable = trip.seatsAvailable - 1;
    await ctx.db.patch(args.tripId, { seatsAvailable: newSeatsAvailable });

    // Notify owner if trip is now full
    if (newSeatsAvailable === 0) {
      await ctx.scheduler.runAfter(0, internal.notifications.notifyTripFull, {
        tripId: args.tripId,
        companyId: trip.companyId,
      });
    }

    // Auto-link traveler to company client list if not already linked
    if (args.travelerId) {
      const existingLink = await ctx.db
        .query("companyTravelers")
        .withIndex("by_company_and_traveler", (q) =>
          q.eq("companyId", company._id).eq("travelerId", args.travelerId!)
        )
        .first();

      if (!existingLink) {
        await ctx.db.insert("companyTravelers", {
          companyId: company._id,
          travelerId: args.travelerId,
        });
      }
    }

    // Record commission if applicable (on ticket price only, not parcels)
    await recordCommission(ctx, bookingId, trip.companyId, trip.priceAmount, trip.currency);

    // Notify owner and traveler of new booking
    const newBooking = await ctx.db.get(bookingId);
    await ctx.scheduler.runAfter(0, internal.notifications.notifyNewBooking, {
      bookingId,
      tripId: args.tripId,
      passengerName: args.passengerName,
      companyId: trip.companyId,
    });

    if (actualTravelerId) {
      await ctx.scheduler.runAfter(0, internal.notifications.notifyBookingConfirmed, {
        bookingId,
        travelerId: actualTravelerId,
        bookingReference: newBooking?.bookingReference ?? "N/A",
        tripId: args.tripId,
      });
    }

    return bookingId;
  },
});

export const markTicketCollected = mutation({
  args: { bookingId: v.id("bookings") },
  handler: async (ctx, args) => {
    const { user, company } = await getSellerCompany(ctx);

    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new ConvexError({ message: "Booking not found", code: "NOT_FOUND" });

    // Verify booking belongs to this company's trip
    const trip = await ctx.db.get(booking.tripId);
    if (!trip || trip.companyId !== company._id)
      throw new ConvexError({ message: "Booking not in your company", code: "FORBIDDEN" });

    if (booking.status === "cancelled")
      throw new ConvexError({ message: "Cannot collect a cancelled booking", code: "BAD_REQUEST" });

    await ctx.db.patch(args.bookingId, {
      status: "collected",
      paymentStatus: "paid",
      soldBySellerId: user._id,
    });
  },
});

export const listCompanyBookings = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getSellerCompany(ctx);

    // Get all upcoming trips for the company
    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    const allBookings = await Promise.all(
      trips.map(async (trip) => {
        const bookings = await ctx.db
          .query("bookings")
          .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
          .collect();

        const route = await ctx.db.get(trip.routeId);
        const bus = await ctx.db.get(trip.busId);
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);

        return bookings.map((b) => ({
          ...b,
          trip: { ...trip, bus, origin, destination, originLoc, destLoc },
        }));
      })
    );

    return allBookings.flat().sort((a, b) =>
      (b._creationTime ?? 0) - (a._creationTime ?? 0)
    );
  },
});
