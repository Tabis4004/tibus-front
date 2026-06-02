import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import type { Id } from "./_generated/dataModel.d.ts";
import { internal } from "./_generated/api.js";
import { resolveStationLocation } from "./stationHelpers.ts";

async function getOwnerCompany(ctx: MutationCtx | QueryCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
  if (user.role !== "owner" && user.role !== "superadmin")
    throw new ConvexError({ message: "Owners only", code: "FORBIDDEN" });
  const company = await ctx.db
    .query("companies")
    .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
    .first();
  if (!company) throw new ConvexError({ message: "No company found", code: "NOT_FOUND" });
  return { user, company };
}

// ─── Routes ───────────────────────────────────────────────────────────────────

export const listRoutes = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return [];
    const company = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    if (!company) return [];

    const routes = await ctx.db
      .query("routes")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    // Hydrate stations
    return await Promise.all(
      routes.map(async (r) => {
        const origin = await ctx.db.get(r.originStationId);
        const destination = await ctx.db.get(r.destinationStationId);
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);
        return { ...r, origin, destination, originLoc, destLoc };
      })
    );
  },
});

export const listRoutesForCompany = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    const routes = await ctx.db
      .query("routes")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .filter((q) => q.eq(q.field("isActive"), true))
      .collect();

    return await Promise.all(
      routes.map(async (r) => {
        const origin = await ctx.db.get(r.originStationId);
        const destination = await ctx.db.get(r.destinationStationId);
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);
        return { ...r, origin, destination, originLoc, destLoc };
      })
    );
  },
});

export const createRoute = mutation({
  args: {
    originStationId: v.id("stations"),
    destinationStationId: v.id("stations"),
    estimatedDurationMinutes: v.number(),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    if (args.originStationId === args.destinationStationId)
      throw new ConvexError({ message: "Origin and destination cannot be the same", code: "BAD_REQUEST" });

    // Verify stations belong to company
    const origin = await ctx.db.get(args.originStationId);
    const dest = await ctx.db.get(args.destinationStationId);
    if (!origin || origin.companyId !== company._id)
      throw new ConvexError({ message: "Origin station not found", code: "NOT_FOUND" });
    if (!dest || dest.companyId !== company._id)
      throw new ConvexError({ message: "Destination station not found", code: "NOT_FOUND" });

    return await ctx.db.insert("routes", {
      companyId: company._id,
      originStationId: args.originStationId,
      destinationStationId: args.destinationStationId,
      estimatedDurationMinutes: args.estimatedDurationMinutes,
      isActive: true,
    });
  },
});

export const updateRoute = mutation({
  args: {
    routeId: v.id("routes"),
    estimatedDurationMinutes: v.number(),
    isActive: v.boolean(),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const route = await ctx.db.get(args.routeId);
    if (!route || route.companyId !== company._id)
      throw new ConvexError({ message: "Route not found", code: "NOT_FOUND" });
    await ctx.db.patch(args.routeId, {
      estimatedDurationMinutes: args.estimatedDurationMinutes,
      isActive: args.isActive,
    });
  },
});

export const deleteRoute = mutation({
  args: { routeId: v.id("routes") },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const route = await ctx.db.get(args.routeId);
    if (!route || route.companyId !== company._id)
      throw new ConvexError({ message: "Route not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.routeId);
  },
});

// ─── Trips ────────────────────────────────────────────────────────────────────

export const listTrips = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return [];
    const company = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    if (!company) return [];

    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .order("desc")
      .collect();

    return await Promise.all(
      trips.map(async (t) => {
        const route = await ctx.db.get(t.routeId);
        const bus = await ctx.db.get(t.busId);
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        return { ...t, route, bus, origin, destination };
      })
    );
  },
});

export const listTripsForCompany = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .filter((q) => q.eq(q.field("status"), "scheduled"))
      .order("asc")
      .collect();

    return await Promise.all(
      trips.map(async (t) => {
        const route = await ctx.db.get(t.routeId);
        const bus = await ctx.db.get(t.busId);
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);
        return { ...t, route, bus, origin, destination, originLoc, destLoc };
      })
    );
  },
});

export const createTrip = mutation({
  args: {
    routeId: v.id("routes"),
    busId: v.id("buses"),
    departureTime: v.string(),
    arrivalTime: v.string(),
    priceAmount: v.number(),
    currency: v.string(),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);

    const route = await ctx.db.get(args.routeId);
    if (!route || route.companyId !== company._id)
      throw new ConvexError({ message: "Route not found", code: "NOT_FOUND" });

    const bus = await ctx.db.get(args.busId);
    if (!bus || bus.companyId !== company._id)
      throw new ConvexError({ message: "Bus not found", code: "NOT_FOUND" });

    const tripId = await ctx.db.insert("trips", {
      companyId: company._id,
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

    // Schedule departure reminder 1 hour before
    const departureMs = new Date(args.departureTime).getTime();
    const reminderMs = departureMs - 60 * 60 * 1000; // 1 hour before
    const now = Date.now();
    if (reminderMs > now) {
      await ctx.scheduler.runAt(reminderMs, internal.notifications.notifyTripDepartureReminder, {
        tripId,
      });
    }

    return tripId;
  },
});

export const updateTripStatus = mutation({
  args: {
    tripId: v.id("trips"),
    status: v.string(),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const trip = await ctx.db.get(args.tripId);
    if (!trip || trip.companyId !== company._id)
      throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });

    const validStatuses = ["scheduled", "active", "cancelled", "completed"];
    if (!validStatuses.includes(args.status))
      throw new ConvexError({ message: "Invalid status", code: "BAD_REQUEST" });

    await ctx.db.patch(args.tripId, { status: args.status });

    // Notify travelers when a trip is cancelled
    if (args.status === "cancelled") {
      await ctx.scheduler.runAfter(0, internal.notifications.notifyTripCancelled, {
        tripId: args.tripId,
      });
    }
  },
});

export const updateTrip = mutation({
  args: {
    tripId: v.id("trips"),
    routeId: v.id("routes"),
    busId: v.id("buses"),
    departureTime: v.string(),
    arrivalTime: v.string(),
    priceAmount: v.number(),
    currency: v.string(),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const trip = await ctx.db.get(args.tripId);
    if (!trip || trip.companyId !== company._id)
      throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });

    const bus = await ctx.db.get(args.busId);
    if (!bus) throw new ConvexError({ message: "Bus not found", code: "NOT_FOUND" });

    await ctx.db.patch(args.tripId, {
      routeId: args.routeId,
      busId: args.busId,
      departureTime: args.departureTime,
      arrivalTime: args.arrivalTime,
      priceAmount: args.priceAmount,
      currency: args.currency,
      totalSeats: bus.capacity,
      seatsAvailable: bus.capacity,
    });
  },
});

// ─── Public query: upcoming trips visible to all users ──────────────────────
export const listUpcomingTripsPublic = query({
  args: {},
  handler: async (ctx) => {
    const now = new Date().toISOString();
    const trips = await ctx.db
      .query("trips")
      .withIndex("by_departure", (q) => q.gte("departureTime", now))
      .order("asc")
      .take(20);

    // Only include scheduled / active trips
    const filtered = trips.filter((t) => t.status === "scheduled" || t.status === "active");

    return await Promise.all(
      filtered.map(async (t) => {
        const route = await ctx.db.get(t.routeId);
        const bus = await ctx.db.get(t.busId);
        const company = await ctx.db.get(t.companyId);
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;
        const originLoc = await resolveStationLocation(ctx, origin);
        const destLoc = await resolveStationLocation(ctx, destination);
        return {
          _id: t._id,
          departureTime: t.departureTime,
          arrivalTime: t.arrivalTime,
          priceAmount: t.priceAmount,
          currency: t.currency,
          seatsAvailable: t.seatsAvailable,
          totalSeats: t.totalSeats,
          status: t.status,
          companyName: company?.name ?? "Unknown",
          busName: bus?.name ?? "",
          originCity: originLoc?.city ?? origin?.name ?? "—",
          destinationCity: destLoc?.city ?? destination?.name ?? "—",
        };
      }),
    );
  },
});

export const deleteTrip = mutation({
  args: { tripId: v.id("trips") },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const trip = await ctx.db.get(args.tripId);
    if (!trip || trip.companyId !== company._id)
      throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.tripId);
  },
});
