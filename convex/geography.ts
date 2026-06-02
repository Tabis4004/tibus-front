import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

// ─── Helpers ────────────────────────────────────────────────────────────────

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

// ─── Countries ──────────────────────────────────────────────────────────────

export const listCountries = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("countries").collect();
  },
});

export const createCountry = mutation({
  args: { name: v.string() },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    // Prevent duplicates (case-insensitive)
    const existing = await ctx.db
      .query("countries")
      .withIndex("by_name", (q) => q.eq("name", args.name.trim()))
      .first();
    if (existing) throw new ConvexError({ message: "Country already exists", code: "CONFLICT" });
    return await ctx.db.insert("countries", { name: args.name.trim() });
  },
});

export const deleteCountry = mutation({
  args: { countryId: v.id("countries") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const country = await ctx.db.get(args.countryId);
    if (!country) throw new ConvexError({ message: "Country not found", code: "NOT_FOUND" });
    // Delete all cities in this country
    const cities = await ctx.db
      .query("cities")
      .withIndex("by_country", (q) => q.eq("countryId", args.countryId))
      .collect();
    for (const city of cities) {
      await ctx.db.delete(city._id);
    }
    await ctx.db.delete(args.countryId);
  },
});

// ─── Cities ─────────────────────────────────────────────────────────────────

export const listCities = query({
  args: { countryId: v.optional(v.id("countries")) },
  handler: async (ctx, args) => {
    if (args.countryId) {
      const cities = await ctx.db
        .query("cities")
        .withIndex("by_country", (q) => q.eq("countryId", args.countryId!))
        .collect();
      // Attach country name
      const country = await ctx.db.get(args.countryId);
      return cities.map((c) => ({ ...c, countryName: country?.name ?? "" }));
    }
    // All cities with country names
    const allCities = await ctx.db.query("cities").collect();
    const countryIds = [...new Set(allCities.map((c) => c.countryId))];
    const countries = await Promise.all(countryIds.map((id) => ctx.db.get(id)));
    const countryMap = new Map(countries.filter(Boolean).map((c) => [c!._id, c!.name]));
    return allCities.map((c) => ({ ...c, countryName: countryMap.get(c.countryId) ?? "" }));
  },
});

export const createCity = mutation({
  args: { countryId: v.id("countries"), name: v.string() },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const country = await ctx.db.get(args.countryId);
    if (!country) throw new ConvexError({ message: "Country not found", code: "NOT_FOUND" });
    return await ctx.db.insert("cities", {
      countryId: args.countryId,
      name: args.name.trim(),
    });
  },
});

export const deleteCity = mutation({
  args: { cityId: v.id("cities") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const city = await ctx.db.get(args.cityId);
    if (!city) throw new ConvexError({ message: "City not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.cityId);
  },
});
