import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";
import type { Id } from "./_generated/dataModel.d.ts";

// ─── Internal V8 helpers for subscription (no "use node") ──────────────────

export const getCompanyForOwner = internalQuery({
  args: { tokenIdentifier: v.string() },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", args.tokenIdentifier))
      .unique();
    if (!user) return null;
    const company = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    return { user, company };
  },
});

export const updateCompanySubscription = internalMutation({
  args: {
    companyId: v.id("companies"),
    planId: v.optional(v.string()),
    subscriptionStatus: v.string(),
    planExpiresAt: v.optional(v.string()),
    paystackCustomerCode: v.optional(v.string()),
    paystackSubscriptionCode: v.optional(v.string()),
    paystackEmailToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.companyId, {
      planId: args.planId,
      subscriptionStatus: args.subscriptionStatus,
      planExpiresAt: args.planExpiresAt,
      paystackCustomerCode: args.paystackCustomerCode ?? undefined,
      paystackSubscriptionCode: args.paystackSubscriptionCode ?? undefined,
      paystackEmailToken: args.paystackEmailToken ?? undefined,
    });
  },
});

export const getCompanyByPaystackCode = internalQuery({
  args: { paystackCustomerCode: v.string() },
  handler: async (ctx, args) => {
    const companies = await ctx.db.query("companies").collect();
    return companies.find((c) => c.paystackCustomerCode === args.paystackCustomerCode) ?? null;
  },
});

export const getPlanById = internalQuery({
  args: { planId: v.string() },
  handler: async (ctx, args) => {
    // Try to get plan by document ID
    try {
      const plan = await ctx.db.get(args.planId as Id<"subscriptionPlans">);
      return plan;
    } catch {
      return null;
    }
  },
});
