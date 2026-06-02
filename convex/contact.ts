import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

// ─── Public: Get WhatsApp number for a given scope ────────────────────────────

export const getWhatsappNumber = query({
  args: { scope: v.string() },
  handler: async (ctx, args) => {
    const setting = await ctx.db
      .query("contactSettings")
      .withIndex("by_scope", (q) => q.eq("scope", args.scope))
      .first();
    return setting?.whatsappNumber ?? null;
  },
});

// ─── Public: Get both platform and company whatsapp numbers ───────────────────

export const getContactOptions = query({
  args: {},
  handler: async (ctx) => {
    // Get platform WhatsApp
    const platform = await ctx.db
      .query("contactSettings")
      .withIndex("by_scope", (q) => q.eq("scope", "platform"))
      .first();

    // Get all company WhatsApp settings
    const companySettings = await ctx.db
      .query("contactSettings")
      .collect();

    const companies = await Promise.all(
      companySettings
        .filter((s) => s.scope !== "platform")
        .map(async (s) => {
          const company = await ctx.db.get(s.scope as never);
          return {
            companyId: s.scope,
            companyName: (company as { name?: string } | null)?.name ?? "Unknown",
            whatsappNumber: s.whatsappNumber,
          };
        })
    );

    return {
      platformWhatsapp: platform?.whatsappNumber ?? null,
      companies,
    };
  },
});

// ─── Public: List companies for the contact form dropdown ─────────────────────

export const listCompaniesForContact = query({
  args: {},
  handler: async (ctx) => {
    const companies = await ctx.db
      .query("companies")
      .collect();
    return companies
      .filter((c) => c.isActive)
      .map((c) => ({ _id: c._id, name: c.name }));
  },
});

// ─── Submit a contact inquiry (no auth required) ──────────────────────────────

export const submitInquiry = mutation({
  args: {
    name: v.string(),
    email: v.string(),
    phone: v.optional(v.string()),
    inquiryTo: v.string(), // "platform" | companyId
    message: v.string(),
  },
  handler: async (ctx, args) => {
    await ctx.db.insert("contactInquiries", {
      name: args.name,
      email: args.email,
      phone: args.phone,
      message: args.message,
      inquiryTo: args.inquiryTo,
      status: "new",
    });
  },
});

// ─── Admin: Set WhatsApp number for platform ──────────────────────────────────

export const setWhatsappNumber = mutation({
  args: {
    scope: v.string(),
    whatsappNumber: v.string(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    // Only superadmin can set platform whatsapp, owners can set their company's
    if (args.scope === "platform" && user.role !== "superadmin") {
      throw new ConvexError({ message: "Only super admins can update platform WhatsApp", code: "FORBIDDEN" });
    }

    if (args.scope !== "platform" && user.role !== "superadmin" && user.role !== "owner") {
      throw new ConvexError({ message: "Not authorized", code: "FORBIDDEN" });
    }

    const existing = await ctx.db
      .query("contactSettings")
      .withIndex("by_scope", (q) => q.eq("scope", args.scope))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        whatsappNumber: args.whatsappNumber,
        updatedBy: user._id,
      });
    } else {
      await ctx.db.insert("contactSettings", {
        scope: args.scope,
        whatsappNumber: args.whatsappNumber,
        updatedBy: user._id,
      });
    }
  },
});

// ─── Admin: List all inquiries ────────────────────────────────────────────────

export const listInquiries = query({
  args: { scope: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return [];

    if (args.scope) {
      const scope: string = args.scope;
      return await ctx.db
        .query("contactInquiries")
        .withIndex("by_inquiryTo", (q) => q.eq("inquiryTo", scope))
        .order("desc")
        .collect();
    }

    // Superadmin sees all
    if (user.role === "superadmin") {
      return await ctx.db
        .query("contactInquiries")
        .order("desc")
        .collect();
    }

    return [];
  },
});

// ─── Admin: Update inquiry status ─────────────────────────────────────────────

export const updateInquiryStatus = mutation({
  args: {
    inquiryId: v.id("contactInquiries"),
    status: v.string(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
    await ctx.db.patch(args.inquiryId, { status: args.status });
  },
});
