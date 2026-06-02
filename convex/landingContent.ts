import { query, mutation } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

// ─── Get all landing content sections ────────────────────────────────────────
export const getAll = query({
  args: {},
  handler: async (ctx) => {
    const sections = await ctx.db.query("landingContent").collect();
    const result: Record<string, string> = {};
    for (const s of sections) {
      result[s.section] = s.content;
    }
    return result;
  },
});

// ─── Get live stats from the database ────────────────────────────────────────
export const getLiveStats = query({
  args: {},
  handler: async (ctx) => {
    // Count active companies
    const allCompanies = await ctx.db.query("companies").collect();
    const activeCompanies = allCompanies.filter((c) => c.isActive);

    // Count completed trips
    const allTrips = await ctx.db.query("trips").collect();
    const completedTrips = allTrips.filter((t) => t.status === "completed");

    // Count travelers (users with role traveler or no role)
    const travelers = await ctx.db
      .query("users")
      .withIndex("by_role", (q) => q.eq("role", "traveler"))
      .collect();
    const noRoleUsers = await ctx.db
      .query("users")
      .withIndex("by_role", (q) => q.eq("role", undefined))
      .collect();
    const totalTravelers = travelers.length + noRoleUsers.length;

    // Count unique cities served (from stations with cityId)
    const stations = await ctx.db.query("stations").collect();
    const cityIds = new Set<string>();
    for (const s of stations) {
      if (s.cityId) cityIds.add(s.cityId);
    }

    return {
      companies: activeCompanies.length,
      trips: completedTrips.length,
      travelers: totalTravelers,
      cities: cityIds.size,
    };
  },
});

// ─── Update a section (superadmin only) ──────────────────────────────────────
export const updateSection = mutation({
  args: {
    section: v.string(),
    content: v.string(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) {
      throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    }
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user || user.role !== "superadmin") {
      throw new ConvexError({ message: "Forbidden", code: "FORBIDDEN" });
    }

    // Upsert
    const existing = await ctx.db
      .query("landingContent")
      .withIndex("by_section", (q) => q.eq("section", args.section))
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, {
        content: args.content,
        updatedBy: user._id,
      });
    } else {
      await ctx.db.insert("landingContent", {
        section: args.section,
        content: args.content,
        updatedBy: user._id,
      });
    }
  },
});
