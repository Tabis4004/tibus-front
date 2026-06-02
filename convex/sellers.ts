import { mutation, query } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { internal } from "./_generated/api.js";

async function getOwnerCompany(ctx: MutationCtx) {
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

export const listSellers = query({
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
    // Find users with role=seller and companyId matching
    const allSellers = await ctx.db
      .query("users")
      .withIndex("by_role", (q) => q.eq("role", "seller"))
      .collect();
    return allSellers.filter((s) => s.companyId === company._id);
  },
});

export const searchUserByEmail = query({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    if (!args.email || args.email.length < 3) return null;
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;
    // Find user with matching email (case-insensitive match via filter)
    const users = await ctx.db.query("users").collect();
    return users.find(
      (u) => u.email?.toLowerCase() === args.email.toLowerCase()
    ) ?? null;
  },
});

export const assignSeller = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const target = await ctx.db.get(args.userId);
    if (!target) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
    if (target.role === "superadmin" || target.role === "owner")
      throw new ConvexError({ message: "Cannot assign this user as a seller", code: "FORBIDDEN" });
    await ctx.db.patch(args.userId, { role: "seller", companyId: company._id });

    // Notify the seller about their assignment
    await ctx.scheduler.runAfter(0, internal.notifications.notifySellerAssigned, {
      sellerId: args.userId,
      companyId: company._id,
    });
  },
});

export const removeSeller = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const target = await ctx.db.get(args.userId);
    if (!target || target.companyId !== company._id)
      throw new ConvexError({ message: "Seller not found in your company", code: "NOT_FOUND" });
    await ctx.db.patch(args.userId, { role: "traveler", companyId: undefined });
  },
});
