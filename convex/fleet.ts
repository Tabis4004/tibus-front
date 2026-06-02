import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { resolveStationLocation } from "./stationHelpers.ts";

async function getOwnerWithCompany(ctx: MutationCtx | QueryCtx) {
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
  if (!company) throw new ConvexError({ message: "No company found. Create your company first.", code: "NOT_FOUND" });
  return { user, company };
}

// ─── Buses ───────────────────────────────────────────────────────────────────

export const listBuses = query({
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
    return await ctx.db
      .query("buses")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();
  },
});

export const createBus = mutation({
  args: {
    name: v.string(),
    plateNumber: v.string(),
    capacity: v.number(),
    busType: v.string(),
    amenities: v.optional(v.array(v.string())),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerWithCompany(ctx);
    return await ctx.db.insert("buses", {
      companyId: company._id,
      name: args.name,
      plateNumber: args.plateNumber,
      capacity: args.capacity,
      busType: args.busType,
      amenities: args.amenities,
      isActive: true,
    });
  },
});

export const updateBus = mutation({
  args: {
    busId: v.id("buses"),
    name: v.string(),
    plateNumber: v.string(),
    capacity: v.number(),
    busType: v.string(),
    amenities: v.optional(v.array(v.string())),
    isActive: v.boolean(),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerWithCompany(ctx);
    const bus = await ctx.db.get(args.busId);
    if (!bus || bus.companyId !== company._id)
      throw new ConvexError({ message: "Bus not found", code: "NOT_FOUND" });
    await ctx.db.patch(args.busId, {
      name: args.name,
      plateNumber: args.plateNumber,
      capacity: args.capacity,
      busType: args.busType,
      amenities: args.amenities,
      isActive: args.isActive,
    });
  },
});

export const deleteBus = mutation({
  args: { busId: v.id("buses") },
  handler: async (ctx, args) => {
    const { company } = await getOwnerWithCompany(ctx);
    const bus = await ctx.db.get(args.busId);
    if (!bus || bus.companyId !== company._id)
      throw new ConvexError({ message: "Bus not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.busId);
  },
});

// ─── Stations ─────────────────────────────────────────────────────────────────

export const listStations = query({
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
    const stations = await ctx.db
      .query("stations")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    return await Promise.all(
      stations.map(async (s) => {
        const location = await resolveStationLocation(ctx, s);
        return { ...s, location };
      }),
    );
  },
});

export const createStation = mutation({
  args: {
    cityId: v.id("cities"),
    name: v.string(),
    address: v.string(),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerWithCompany(ctx);
    const city = await ctx.db.get(args.cityId);
    if (!city)
      throw new ConvexError({ message: "City not found", code: "NOT_FOUND" });
    return await ctx.db.insert("stations", {
      companyId: company._id,
      cityId: args.cityId,
      name: args.name,
      address: args.address,
      latitude: args.latitude,
      longitude: args.longitude,
      isActive: true,
    });
  },
});

export const updateStation = mutation({
  args: {
    stationId: v.id("stations"),
    name: v.string(),
    address: v.string(),
    isActive: v.boolean(),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerWithCompany(ctx);
    const station = await ctx.db.get(args.stationId);
    if (!station || station.companyId !== company._id)
      throw new ConvexError({ message: "Station not found", code: "NOT_FOUND" });
    await ctx.db.patch(args.stationId, {
      name: args.name,
      address: args.address,
      isActive: args.isActive,
      latitude: args.latitude,
      longitude: args.longitude,
    });
  },
});

export const deleteStation = mutation({
  args: { stationId: v.id("stations") },
  handler: async (ctx, args) => {
    const { company } = await getOwnerWithCompany(ctx);
    const station = await ctx.db.get(args.stationId);
    if (!station || station.companyId !== company._id)
      throw new ConvexError({ message: "Station not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.stationId);
  },
});
