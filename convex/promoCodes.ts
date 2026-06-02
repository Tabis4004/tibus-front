import { query, mutation } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function getOwnerCompany(ctx: MutationCtx | QueryCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!user || (user.role !== "owner" && user.role !== "superadmin"))
    throw new ConvexError({ message: "Access denied", code: "FORBIDDEN" });

  const company = await ctx.db
    .query("companies")
    .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
    .first();
  if (!company) throw new ConvexError({ message: "No company found", code: "NOT_FOUND" });

  return { user, company };
}

// ─── Queries ─────────────────────────────────────────────────────────────────

export const listPromoCodes = query({
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

    const codes = await ctx.db
      .query("promoCodes")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    // Enrich with route info
    const enriched = await Promise.all(
      codes.map(async (code) => {
        const route = code.routeId ? await ctx.db.get(code.routeId) : null;
        let routeLabel: string | null = null;
        if (route) {
          const origin = await ctx.db.get(route.originStationId);
          const dest = await ctx.db.get(route.destinationStationId);
          routeLabel = `${origin?.name ?? "?"} → ${dest?.name ?? "?"}`;
        }
        return { ...code, routeLabel };
      })
    );

    return enriched;
  },
});

/** Validate a promo code for a specific trip (used by travelers & sellers) */
export const validatePromoCode = query({
  args: {
    code: v.string(),
    tripId: v.id("trips"),
  },
  handler: async (ctx, args) => {
    const trip = await ctx.db.get(args.tripId);
    if (!trip) return { valid: false, error: "Trip not found" };

    const promo = await ctx.db
      .query("promoCodes")
      .withIndex("by_company_and_code", (q) =>
        q.eq("companyId", trip.companyId).eq("code", args.code.toUpperCase().trim())
      )
      .first();

    if (!promo) return { valid: false, error: "Code invalide" };
    if (!promo.isActive) return { valid: false, error: "Code désactivé" };

    const now = new Date().toISOString();
    if (now < promo.validFrom) return { valid: false, error: "Code pas encore valide" };
    if (now > promo.validUntil) return { valid: false, error: "Code expiré" };

    if (promo.maxUsage && promo.usageCount >= promo.maxUsage)
      return { valid: false, error: "Limite d'utilisation atteinte" };

    // Route restriction
    if (promo.routeId && promo.routeId !== trip.routeId)
      return { valid: false, error: "Code non applicable à ce trajet" };

    // Calculate discount
    let discountAmount = 0;
    if (promo.discountType === "percentage") {
      discountAmount = Math.round((trip.priceAmount * promo.discountValue) / 100);
    } else {
      discountAmount = promo.discountValue;
    }

    // Cap discount at ticket price
    discountAmount = Math.min(discountAmount, trip.priceAmount);

    return {
      valid: true,
      promoId: promo._id,
      discountType: promo.discountType,
      discountValue: promo.discountValue,
      discountAmount,
      code: promo.code,
    };
  },
});

// ─── Mutations ───────────────────────────────────────────────────────────────

export const createPromoCode = mutation({
  args: {
    code: v.string(),
    discountType: v.string(),
    discountValue: v.number(),
    currency: v.optional(v.string()),
    validFrom: v.string(),
    validUntil: v.string(),
    maxUsage: v.optional(v.number()),
    routeId: v.optional(v.id("routes")),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);

    const normalizedCode = args.code.toUpperCase().trim();
    if (!normalizedCode || normalizedCode.length < 3)
      throw new ConvexError({ message: "Code must be at least 3 characters", code: "BAD_REQUEST" });

    // Verify uniqueness within company
    const existing = await ctx.db
      .query("promoCodes")
      .withIndex("by_company_and_code", (q) =>
        q.eq("companyId", company._id).eq("code", normalizedCode)
      )
      .first();
    if (existing)
      throw new ConvexError({ message: "A promo code with this name already exists", code: "CONFLICT" });

    if (args.discountType !== "percentage" && args.discountType !== "fixed")
      throw new ConvexError({ message: "Invalid discount type", code: "BAD_REQUEST" });

    if (args.discountValue <= 0)
      throw new ConvexError({ message: "Discount value must be positive", code: "BAD_REQUEST" });

    if (args.discountType === "percentage" && args.discountValue > 100)
      throw new ConvexError({ message: "Percentage cannot exceed 100", code: "BAD_REQUEST" });

    return await ctx.db.insert("promoCodes", {
      companyId: company._id,
      code: normalizedCode,
      discountType: args.discountType,
      discountValue: args.discountValue,
      currency: args.currency,
      validFrom: args.validFrom,
      validUntil: args.validUntil,
      maxUsage: args.maxUsage,
      usageCount: 0,
      routeId: args.routeId,
      isActive: true,
    });
  },
});

export const updatePromoCode = mutation({
  args: {
    promoId: v.id("promoCodes"),
    discountType: v.optional(v.string()),
    discountValue: v.optional(v.number()),
    validFrom: v.optional(v.string()),
    validUntil: v.optional(v.string()),
    maxUsage: v.optional(v.number()),
    routeId: v.optional(v.id("routes")),
    isActive: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const promo = await ctx.db.get(args.promoId);
    if (!promo || promo.companyId !== company._id)
      throw new ConvexError({ message: "Promo code not found", code: "NOT_FOUND" });

    const patch: Record<string, unknown> = {};
    if (args.discountType !== undefined) patch.discountType = args.discountType;
    if (args.discountValue !== undefined) patch.discountValue = args.discountValue;
    if (args.validFrom !== undefined) patch.validFrom = args.validFrom;
    if (args.validUntil !== undefined) patch.validUntil = args.validUntil;
    if (args.maxUsage !== undefined) patch.maxUsage = args.maxUsage;
    if (args.routeId !== undefined) patch.routeId = args.routeId;
    if (args.isActive !== undefined) patch.isActive = args.isActive;

    await ctx.db.patch(args.promoId, patch);
  },
});

export const deletePromoCode = mutation({
  args: { promoId: v.id("promoCodes") },
  handler: async (ctx, args) => {
    const { company } = await getOwnerCompany(ctx);
    const promo = await ctx.db.get(args.promoId);
    if (!promo || promo.companyId !== company._id)
      throw new ConvexError({ message: "Promo code not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.promoId);
  },
});

/** Increment usage count when a promo code is applied to a booking */
export const usePromoCode = mutation({
  args: { promoId: v.id("promoCodes") },
  handler: async (ctx, args) => {
    const promo = await ctx.db.get(args.promoId);
    if (!promo) throw new ConvexError({ message: "Promo code not found", code: "NOT_FOUND" });
    await ctx.db.patch(args.promoId, { usageCount: promo.usageCount + 1 });
  },
});
