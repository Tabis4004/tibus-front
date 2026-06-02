import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { recordCommission } from "./commissionHelpers.ts";
import { internal } from "./_generated/api.js";

// Helper: ensure caller is SuperAdmin
async function requireAdmin(ctx: MutationCtx | QueryCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!user || user.role !== "superadmin")
    throw new ConvexError({ message: "SuperAdmin only", code: "FORBIDDEN" });
  return user;
}

function generateRef(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let ref = "TB-";
  for (let i = 0; i < 8; i++) {
    ref += chars[Math.floor(Math.random() * chars.length)];
  }
  return ref;
}

// ─── Stations (now using global cities) ────────────────────────────────────

export const listStations = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const stations = await ctx.db
      .query("stations")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .collect();

    return await Promise.all(
      stations.map(async (s) => {
        // Resolve city info (new model) or legacy location
        let cityName = "";
        let countryName = "";
        if (s.cityId) {
          const city = await ctx.db.get(s.cityId);
          if (city) {
            cityName = city.name;
            const country = await ctx.db.get(city.countryId);
            countryName = country?.name ?? "";
          }
        } else if (s.locationId) {
          const loc = await ctx.db.get(s.locationId);
          if (loc) {
            cityName = loc.city;
            countryName = loc.country;
          }
        }
        return {
          ...s,
          location: { city: cityName, country: countryName },
        };
      }),
    );
  },
});

export const createStation = mutation({
  args: {
    companyId: v.id("companies"),
    cityId: v.id("cities"),
    name: v.string(),
    address: v.string(),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const city = await ctx.db.get(args.cityId);
    if (!city) throw new ConvexError({ message: "City not found", code: "NOT_FOUND" });
    return await ctx.db.insert("stations", {
      companyId: args.companyId,
      cityId: args.cityId,
      name: args.name,
      address: args.address,
      latitude: args.latitude,
      longitude: args.longitude,
      isActive: true,
    });
  },
});

export const deleteStation = mutation({
  args: { stationId: v.id("stations") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const station = await ctx.db.get(args.stationId);
    if (!station) throw new ConvexError({ message: "Station not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.stationId);
  },
});

// ─── Buses ──────────────────────────────────────────────────────────────────

export const listBuses = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    return await ctx.db
      .query("buses")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .collect();
  },
});

export const createBus = mutation({
  args: {
    companyId: v.id("companies"),
    name: v.string(),
    plateNumber: v.string(),
    capacity: v.number(),
    busType: v.string(),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    return await ctx.db.insert("buses", {
      companyId: args.companyId,
      name: args.name,
      plateNumber: args.plateNumber,
      capacity: args.capacity,
      busType: args.busType,
      isActive: true,
    });
  },
});

export const deleteBus = mutation({
  args: { busId: v.id("buses") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const bus = await ctx.db.get(args.busId);
    if (!bus) throw new ConvexError({ message: "Bus not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.busId);
  },
});

// ─── Routes ─────────────────────────────────────────────────────────────────

export const listRoutes = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const routes = await ctx.db
      .query("routes")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .collect();
    return await Promise.all(
      routes.map(async (r) => {
        const origin = await ctx.db.get(r.originStationId);
        const destination = await ctx.db.get(r.destinationStationId);
        // Resolve city/country for each station
        const resolveStation = async (station: typeof origin) => {
          if (!station) return null;
          let city = "";
          let country = "";
          if (station.cityId) {
            const c = await ctx.db.get(station.cityId);
            if (c) {
              city = c.name;
              const co = await ctx.db.get(c.countryId);
              country = co?.name ?? "";
            }
          } else if (station.locationId) {
            const loc = await ctx.db.get(station.locationId);
            if (loc) { city = loc.city; country = loc.country; }
          }
          return { city, country };
        };
        const originLoc = await resolveStation(origin);
        const destLoc = await resolveStation(destination);
        return { ...r, origin, destination, originLoc, destLoc };
      }),
    );
  },
});

export const createRoute = mutation({
  args: {
    companyId: v.id("companies"),
    originStationId: v.id("stations"),
    destinationStationId: v.id("stations"),
    estimatedDurationMinutes: v.number(),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    if (args.originStationId === args.destinationStationId)
      throw new ConvexError({ message: "Origin and destination cannot be the same", code: "BAD_REQUEST" });
    return await ctx.db.insert("routes", {
      companyId: args.companyId,
      originStationId: args.originStationId,
      destinationStationId: args.destinationStationId,
      estimatedDurationMinutes: args.estimatedDurationMinutes,
      isActive: true,
    });
  },
});

export const deleteRoute = mutation({
  args: { routeId: v.id("routes") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const route = await ctx.db.get(args.routeId);
    if (!route) throw new ConvexError({ message: "Route not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.routeId);
  },
});

// ─── Trips ──────────────────────────────────────────────────────────────────

export const listTrips = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .order("desc")
      .collect();
    return await Promise.all(
      trips.map(async (t) => {
        const route = await ctx.db.get(t.routeId);
        const bus = await ctx.db.get(t.busId);
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        return { ...t, route, bus, origin, destination };
      }),
    );
  },
});

export const createTrip = mutation({
  args: {
    companyId: v.id("companies"),
    routeId: v.id("routes"),
    busId: v.id("buses"),
    departureTime: v.string(),
    arrivalTime: v.string(),
    priceAmount: v.number(),
    currency: v.string(),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const bus = await ctx.db.get(args.busId);
    if (!bus) throw new ConvexError({ message: "Bus not found", code: "NOT_FOUND" });
    return await ctx.db.insert("trips", {
      companyId: args.companyId,
      routeId: args.routeId,
      busId: args.busId,
      departureTime: args.departureTime,
      arrivalTime: args.arrivalTime,
      priceAmount: args.priceAmount,
      currency: args.currency,
      seatsAvailable: bus.capacity,
      totalSeats: bus.capacity,
      status: "scheduled",
    });
  },
});

export const updateTripStatus = mutation({
  args: { tripId: v.id("trips"), status: v.string() },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const validStatuses = ["scheduled", "active", "cancelled", "completed"];
    if (!validStatuses.includes(args.status))
      throw new ConvexError({ message: "Invalid status", code: "BAD_REQUEST" });
    await ctx.db.patch(args.tripId, { status: args.status });
  },
});

export const deleteTrip = mutation({
  args: { tripId: v.id("trips") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const trip = await ctx.db.get(args.tripId);
    if (!trip) throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.tripId);
  },
});

// ─── Ticket Sales ───────────────────────────────────────────────────────────

export const sellTicket = mutation({
  args: {
    tripId: v.id("trips"),
    passengerName: v.string(),
    passengerPhone: v.optional(v.string()),
    seatNumber: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const trip = await ctx.db.get(args.tripId);
    if (!trip) throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });
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

    const bookingId = await ctx.db.insert("bookings", {
      tripId: args.tripId,
      travelerId: admin._id,
      soldBySellerId: admin._id,
      passengerName: args.passengerName,
      passengerPhone: args.passengerPhone,
      seatNumber: args.seatNumber,
      status: "confirmed",
      totalPrice: trip.priceAmount,
      currency: trip.currency,
      bookingReference: generateRef(),
      paymentStatus: "paid",
    });

    await ctx.db.patch(args.tripId, { seatsAvailable: trip.seatsAvailable - 1 });

    // Notify owner if trip is now full
    if (trip.seatsAvailable - 1 === 0) {
      await ctx.scheduler.runAfter(0, internal.notifications.notifyTripFull, {
        tripId: args.tripId,
        companyId: trip.companyId,
      });
    }

    // Record commission if applicable
    await recordCommission(ctx, bookingId, trip.companyId, trip.priceAmount, trip.currency);

    return bookingId;
  },
});

export const listBookings = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .collect();

    const allBookings = await Promise.all(
      trips.map(async (trip) => {
        const bookings = await ctx.db
          .query("bookings")
          .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
          .collect();
        const route = await ctx.db.get(trip.routeId);
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        return bookings.map((b) => ({
          ...b,
          trip,
          origin,
          destination,
        }));
      }),
    );
    return allBookings.flat().sort((a, b) => b._creationTime - a._creationTime);
  },
});
