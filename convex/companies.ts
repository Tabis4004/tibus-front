import { mutation, query } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

// ─── File upload for company logos ───────────────────────────────────────────

export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    return await ctx.storage.generateUploadUrl();
  },
});

export const getLogoUrl = query({
  args: { storageId: v.id("_storage") },
  handler: async (ctx, args) => {
    return await ctx.storage.getUrl(args.storageId);
  },
});

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function getOwnerUser(ctx: MutationCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
  if (user.role !== "owner" && user.role !== "superadmin")
    throw new ConvexError({ message: "Only company owners can perform this action", code: "FORBIDDEN" });
  return user;
}

export const getMyCompany = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return null;
    return await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
  },
});

export const getCompanyById = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.companyId);
  },
});

export const listActiveCompanies = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db
      .query("companies")
      .filter((q) => q.eq(q.field("isActive"), true))
      .collect();
  },
});

export const createCompany = mutation({
  args: {
    name: v.string(),
    description: v.optional(v.string()),
    logoUrl: v.optional(v.string()),
    logoStorageId: v.optional(v.id("_storage")),
    phone: v.optional(v.string()),
    email: v.optional(v.string()),
    website: v.optional(v.string()),
    countryId: v.optional(v.id("countries")),
    address: v.optional(v.string()),
    nif: v.optional(v.string()),
    rccm: v.optional(v.string()),
    tva: v.optional(v.string()),
    bankAccount: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await getOwnerUser(ctx);
    const existing = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    if (existing) throw new ConvexError({ message: "You already have a company", code: "CONFLICT" });

    // Find default trial plan and auto-assign
    const plans = await ctx.db
      .query("subscriptionPlans")
      .collect();
    const defaultPlan = plans.find((p) => p.isDefault && p.isActive);

    const trialExpiresAt = defaultPlan
      ? new Date(Date.now() + defaultPlan.durationDays * 24 * 60 * 60 * 1000).toISOString()
      : undefined;

    return await ctx.db.insert("companies", {
      ownerId: user._id,
      name: args.name,
      description: args.description,
      logoUrl: args.logoUrl,
      logoStorageId: args.logoStorageId,
      phone: args.phone,
      email: args.email,
      website: args.website,
      countryId: args.countryId,
      address: args.address,
      nif: args.nif,
      rccm: args.rccm,
      tva: args.tva,
      bankAccount: args.bankAccount,
      isActive: true,
      subscriptionPlanId: defaultPlan?._id,
      subscriptionStatus: defaultPlan ? "trial" : "none",
      planExpiresAt: trialExpiresAt,
    });
  },
});

export const updateCompany = mutation({
  args: {
    companyId: v.id("companies"),
    name: v.string(),
    description: v.optional(v.string()),
    logoUrl: v.optional(v.string()),
    logoStorageId: v.optional(v.id("_storage")),
    phone: v.optional(v.string()),
    email: v.optional(v.string()),
    website: v.optional(v.string()),
    countryId: v.optional(v.id("countries")),
    address: v.optional(v.string()),
    boardingMessage: v.optional(v.string()),
    nif: v.optional(v.string()),
    rccm: v.optional(v.string()),
    tva: v.optional(v.string()),
    bankAccount: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await getOwnerUser(ctx);
    const company = await ctx.db.get(args.companyId);
    if (!company) throw new ConvexError({ message: "Company not found", code: "NOT_FOUND" });
    if (company.ownerId !== user._id && user.role !== "superadmin")
      throw new ConvexError({ message: "Not your company", code: "FORBIDDEN" });

    await ctx.db.patch(args.companyId, {
      name: args.name,
      description: args.description,
      logoUrl: args.logoUrl,
      logoStorageId: args.logoStorageId,
      phone: args.phone,
      email: args.email,
      website: args.website,
      countryId: args.countryId,
      address: args.address,
      boardingMessage: args.boardingMessage,
      nif: args.nif,
      rccm: args.rccm,
      tva: args.tva,
      bankAccount: args.bankAccount,
    });
  },
});

export const listAllCompanies = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];
    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user || user.role !== "superadmin") return [];
    return await ctx.db.query("companies").collect();
  },
});

export const toggleCompanyActive = mutation({
  args: { companyId: v.id("companies"), isActive: v.boolean() },
  handler: async (ctx, args) => {
    const user = await getOwnerUser(ctx);
    const company = await ctx.db.get(args.companyId);
    if (!company) throw new ConvexError({ message: "Company not found", code: "NOT_FOUND" });
    if (company.ownerId !== user._id && user.role !== "superadmin")
      throw new ConvexError({ message: "Not your company", code: "FORBIDDEN" });
    await ctx.db.patch(args.companyId, { isActive: args.isActive });
  },
});

// ─── SuperAdmin: create company for any user ─────────────────────────────────

export const adminCreateCompany = mutation({
  args: {
    ownerId: v.id("users"),
    name: v.string(),
    description: v.optional(v.string()),
    phone: v.optional(v.string()),
    email: v.optional(v.string()),
    website: v.optional(v.string()),
    countryId: v.optional(v.id("countries")),
    address: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const caller = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!caller || caller.role !== "superadmin")
      throw new ConvexError({ message: "Forbidden: SuperAdmin only", code: "FORBIDDEN" });

    const owner = await ctx.db.get(args.ownerId);
    if (!owner) throw new ConvexError({ message: "Owner user not found", code: "NOT_FOUND" });

    // Check if the owner already has a company
    const existing = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", args.ownerId))
      .first();
    if (existing) throw new ConvexError({ message: "This user already has a company", code: "CONFLICT" });

    // Auto-upgrade user role to owner if they are a traveler
    if (owner.role === "traveler" || !owner.role) {
      await ctx.db.patch(args.ownerId, { role: "owner" });
    }

    // Find default trial plan and auto-assign
    const plans = await ctx.db
      .query("subscriptionPlans")
      .collect();
    const defaultPlan = plans.find((p) => p.isDefault && p.isActive);
    const trialExpiresAt = defaultPlan
      ? new Date(Date.now() + defaultPlan.durationDays * 24 * 60 * 60 * 1000).toISOString()
      : undefined;

    return await ctx.db.insert("companies", {
      ownerId: args.ownerId,
      name: args.name,
      description: args.description,
      phone: args.phone,
      email: args.email,
      website: args.website,
      countryId: args.countryId,
      address: args.address,
      isActive: true,
      subscriptionPlanId: defaultPlan?._id,
      subscriptionStatus: defaultPlan ? "trial" : "none",
      planExpiresAt: trialExpiresAt,
    });
  },
});

// ─── SuperAdmin: set company subscription plan directly ───────────────────────

export const adminSetSubscription = mutation({
  args: {
    companyId: v.id("companies"),
    planId: v.string(),
    subscriptionStatus: v.string(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const caller = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!caller || caller.role !== "superadmin")
      throw new ConvexError({ message: "Forbidden: SuperAdmin only", code: "FORBIDDEN" });

    const company = await ctx.db.get(args.companyId);
    if (!company) throw new ConvexError({ message: "Company not found", code: "NOT_FOUND" });

    const validPlans = ["basic", "pro", "none"];
    if (!validPlans.includes(args.planId))
      throw new ConvexError({ message: "Invalid plan", code: "BAD_REQUEST" });

    const validStatuses = ["active", "past_due", "cancelled", "none"];
    if (!validStatuses.includes(args.subscriptionStatus))
      throw new ConvexError({ message: "Invalid status", code: "BAD_REQUEST" });

    const expiresAt = args.subscriptionStatus === "active"
      ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
      : company.planExpiresAt;

    await ctx.db.patch(args.companyId, {
      planId: args.planId === "none" ? undefined : args.planId,
      subscriptionStatus: args.subscriptionStatus,
      planExpiresAt: expiresAt,
    });
  },
});

// ─── SuperAdmin: delete company ────────────────────────────────────────────────

export const adminDeleteCompany = mutation({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    const caller = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!caller || caller.role !== "superadmin")
      throw new ConvexError({ message: "Forbidden: SuperAdmin only", code: "FORBIDDEN" });

    const company = await ctx.db.get(args.companyId);
    if (!company) throw new ConvexError({ message: "Company not found", code: "NOT_FOUND" });

    await ctx.db.patch(args.companyId, { isActive: false });
  },
});

// ─── Owner: get routes for their company (used in promo code form) ────────────

export const getMyCompanyRoutes = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user || (user.role !== "owner" && user.role !== "superadmin")) return [];

    const company = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    if (!company) return [];

    const routes = await ctx.db
      .query("routes")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    const enriched = await Promise.all(
      routes.filter((r) => r.isActive).map(async (r) => {
        const origin = await ctx.db.get(r.originStationId);
        const dest = await ctx.db.get(r.destinationStationId);
        return {
          _id: r._id,
          originName: origin?.name ?? "?",
          destName: dest?.name ?? "?",
        };
      })
    );
    return enriched;
  },
});
