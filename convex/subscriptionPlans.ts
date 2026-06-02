import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

// ─── Queries ─────────────────────────────────────────────────────────────────

export const listAll = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("subscriptionPlans").collect();
  },
});

export const listActive = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db
      .query("subscriptionPlans")
      .withIndex("by_active", (q) => q.eq("isActive", true))
      .collect();
  },
});

export const getDefault = query({
  args: {},
  handler: async (ctx) => {
    const plans = await ctx.db
      .query("subscriptionPlans")
      .withIndex("by_active", (q) => q.eq("isActive", true))
      .collect();
    return plans.find((p) => p.isDefault) ?? null;
  },
});

// ─── Mutations (SuperAdmin only) ─────────────────────────────────────────────

export const create = mutation({
  args: {
    name: v.string(),
    durationDays: v.number(),
    price: v.number(),
    currency: v.string(),
    isDefault: v.boolean(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user || user.role !== "superadmin")
      throw new ConvexError({ message: "Forbidden: SuperAdmin only", code: "FORBIDDEN" });

    // If setting as default, unset any existing default
    if (args.isDefault) {
      const existing = await ctx.db.query("subscriptionPlans").collect();
      for (const plan of existing) {
        if (plan.isDefault) {
          await ctx.db.patch(plan._id, { isDefault: false });
        }
      }
    }

    return await ctx.db.insert("subscriptionPlans", {
      name: args.name,
      durationDays: args.durationDays,
      price: args.price,
      currency: args.currency,
      isDefault: args.isDefault,
      isActive: true,
    });
  },
});

export const update = mutation({
  args: {
    planId: v.id("subscriptionPlans"),
    name: v.optional(v.string()),
    durationDays: v.optional(v.number()),
    price: v.optional(v.number()),
    currency: v.optional(v.string()),
    isDefault: v.optional(v.boolean()),
    isActive: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user || user.role !== "superadmin")
      throw new ConvexError({ message: "Forbidden: SuperAdmin only", code: "FORBIDDEN" });

    const plan = await ctx.db.get(args.planId);
    if (!plan) throw new ConvexError({ message: "Plan not found", code: "NOT_FOUND" });

    // If setting as default, unset any existing default
    if (args.isDefault) {
      const existing = await ctx.db.query("subscriptionPlans").collect();
      for (const p of existing) {
        if (p.isDefault && p._id !== args.planId) {
          await ctx.db.patch(p._id, { isDefault: false });
        }
      }
    }

    const patch: Record<string, unknown> = {};
    if (args.name !== undefined) patch.name = args.name;
    if (args.durationDays !== undefined) patch.durationDays = args.durationDays;
    if (args.price !== undefined) patch.price = args.price;
    if (args.currency !== undefined) patch.currency = args.currency;
    if (args.isDefault !== undefined) patch.isDefault = args.isDefault;
    if (args.isActive !== undefined) patch.isActive = args.isActive;

    await ctx.db.patch(args.planId, patch);
  },
});

export const remove = mutation({
  args: { planId: v.id("subscriptionPlans") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user || user.role !== "superadmin")
      throw new ConvexError({ message: "Forbidden: SuperAdmin only", code: "FORBIDDEN" });

    await ctx.db.delete(args.planId);
  },
});
