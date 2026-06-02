import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import type { MutationCtx, QueryCtx } from "./_generated/server";

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function requireSuperAdmin(ctx: MutationCtx | QueryCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity)
    throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!user || user.role !== "superadmin")
    throw new ConvexError({ message: "SuperAdmin only", code: "FORBIDDEN" });
  return user;
}

// ─── Commission settings CRUD ─────────────────────────────────────────────────

export const getCompanyCommission = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;
    return await ctx.db
      .query("companyCommissions")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .first();
  },
});

export const setCompanyCommission = mutation({
  args: {
    companyId: v.id("companies"),
    rate: v.number(),
    paidBy: v.string(),
  },
  handler: async (ctx, args) => {
    const admin = await requireSuperAdmin(ctx);

    if (args.rate < 0 || args.rate > 100)
      throw new ConvexError({ message: "Rate must be between 0 and 100", code: "BAD_REQUEST" });
    if (args.paidBy !== "traveler" && args.paidBy !== "company")
      throw new ConvexError({ message: "paidBy must be 'traveler' or 'company'", code: "BAD_REQUEST" });

    const existing = await ctx.db
      .query("companyCommissions")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        rate: args.rate,
        paidBy: args.paidBy,
        updatedBy: admin._id,
      });
    } else {
      await ctx.db.insert("companyCommissions", {
        companyId: args.companyId,
        rate: args.rate,
        paidBy: args.paidBy,
        updatedBy: admin._id,
      });
    }
  },
});

// ─── Commission entries queries ───────────────────────────────────────────────

export const listAllCommissions = query({
  args: {},
  handler: async (ctx) => {
    await requireSuperAdmin(ctx);

    const entries = await ctx.db
      .query("commissionEntries")
      .order("desc")
      .collect();

    return await Promise.all(
      entries.map(async (e) => {
        const company = await ctx.db.get(e.companyId);
        const booking = await ctx.db.get(e.bookingId);
        return {
          ...e,
          companyName: company?.name ?? "Unknown",
          bookingRef: booking?.bookingReference ?? "—",
          passengerName: booking?.passengerName ?? "—",
        };
      })
    );
  },
});

export const listCompanyCommissions = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];

    const entries = await ctx.db
      .query("commissionEntries")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .order("desc")
      .collect();

    return await Promise.all(
      entries.map(async (e) => {
        const booking = await ctx.db.get(e.bookingId);
        return {
          ...e,
          bookingRef: booking?.bookingReference ?? "—",
          passengerName: booking?.passengerName ?? "—",
        };
      })
    );
  },
});

export const getCommissionSummary = query({
  args: {},
  handler: async (ctx) => {
    await requireSuperAdmin(ctx);

    const entries = await ctx.db
      .query("commissionEntries")
      .collect();

    // Group by company
    const byCompany = new Map<string, { companyId: string; pending: number; paid: number; currency: string }>();

    for (const e of entries) {
      const key = e.companyId;
      if (!byCompany.has(key)) {
        byCompany.set(key, { companyId: key, pending: 0, paid: 0, currency: e.currency });
      }
      const rec = byCompany.get(key)!;
      if (e.status === "pending") {
        rec.pending += e.amount;
      } else {
        rec.paid += e.amount;
      }
    }

    const results = [];
    for (const [, rec] of byCompany) {
      const company = await ctx.db.get(rec.companyId as never);
      results.push({
        companyId: rec.companyId,
        companyName: (company as { name?: string } | null)?.name ?? "Unknown",
        pending: rec.pending,
        paid: rec.paid,
        balance: rec.pending,
        currency: rec.currency,
      });
    }

    return results;
  },
});

// ─── Mark commissions as paid ─────────────────────────────────────────────────

export const markCommissionsPaid = mutation({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    await requireSuperAdmin(ctx);

    const pendingEntries = await ctx.db
      .query("commissionEntries")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .collect();

    const now = new Date().toISOString();
    let count = 0;
    for (const entry of pendingEntries) {
      if (entry.status === "pending") {
        await ctx.db.patch(entry._id, { status: "paid", paidAt: now });
        count++;
      }
    }

    return { markedPaid: count };
  },
});

// ─── Owner: view own company commissions ──────────────────────────────────────

export const getOwnerCommissions = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return null;

    const company = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    if (!company) return null;

    const settings = await ctx.db
      .query("companyCommissions")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .first();

    const entries = await ctx.db
      .query("commissionEntries")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .order("desc")
      .collect();

    let pendingTotal = 0;
    let paidTotal = 0;
    const enriched = await Promise.all(
      entries.map(async (e) => {
        if (e.status === "pending") pendingTotal += e.amount;
        else paidTotal += e.amount;
        const booking = await ctx.db.get(e.bookingId);
        return {
          ...e,
          bookingRef: booking?.bookingReference ?? "—",
          passengerName: booking?.passengerName ?? "—",
        };
      })
    );

    return {
      rate: settings?.rate ?? 0,
      paidBy: settings?.paidBy ?? "company",
      pendingTotal,
      paidTotal,
      currency: entries[0]?.currency ?? "XAF",
      entries: enriched,
    };
  },
});
