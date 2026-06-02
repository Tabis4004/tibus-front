import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

// SuperAdmin bootstrap email — this email is auto-assigned superadmin on first login
const SUPERADMIN_EMAIL = "isidoretabati@gmail.com";

export const updateCurrentUser = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;

    const existing = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();

    // Determine role for new users — superadmin bootstrap by email
    const isSuperAdmin = identity.email === SUPERADMIN_EMAIL;

    if (existing) {
      // Auto-upgrade to superadmin if email matches and not already superadmin
      if (isSuperAdmin && existing.role !== "superadmin") {
        await ctx.db.patch(existing._id, {
          name: identity.name,
          email: identity.email,
          avatar: identity.profileUrl,
          role: "superadmin",
        });
      } else {
        await ctx.db.patch(existing._id, {
          name: identity.name,
          email: identity.email,
          avatar: identity.profileUrl,
        });
      }
      return existing._id;
    }

    const userId = await ctx.db.insert("users", {
      tokenIdentifier: identity.tokenIdentifier,
      name: identity.name,
      email: identity.email,
      avatar: identity.profileUrl,
      role: isSuperAdmin ? "superadmin" : "traveler",
    });
    return userId;
  },
});

export const getCurrentUser = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;

    return await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
  },
});

export const requestOwnerRole = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();

    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
    if (user.role === "owner") throw new ConvexError({ message: "Already an owner", code: "CONFLICT" });
    if (user.role === "superadmin") throw new ConvexError({ message: "SuperAdmins cannot be owners", code: "FORBIDDEN" });

    await ctx.db.patch(user._id, { role: "owner" });
  },
});

export const completeProfile = mutation({
  args: {
    fullName: v.string(),
    username: v.string(),
    phone: v.string(),
    email: v.optional(v.string()),
    countryId: v.id("countries"),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();

    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    // Validate username uniqueness
    const existingUsername = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", args.username.trim().toLowerCase()))
      .first();

    if (existingUsername && existingUsername._id !== user._id) {
      throw new ConvexError({ message: "Username already taken", code: "CONFLICT" });
    }

    // Verify country exists
    const country = await ctx.db.get(args.countryId);
    if (!country) throw new ConvexError({ message: "Country not found", code: "NOT_FOUND" });

    await ctx.db.patch(user._id, {
      name: args.fullName.trim(),
      username: args.username.trim().toLowerCase(),
      phone: args.phone.trim(),
      email: args.email?.trim() || user.email,
      countryId: args.countryId,
      profileCompleted: true,
      onboardingCompleted: false,
    });

    return user._id;
  },
});

// ─── Admin-only queries & mutations ───────────────────────────────────────────

async function requireSuperAdmin(ctx: { auth: { getUserIdentity: () => Promise<{ tokenIdentifier: string } | null> }, db: { query: (table: string) => { withIndex: (index: string, fn: (q: { eq: (field: string, value: string) => unknown }) => unknown) => { unique: () => Promise<{ role?: string } | null> } } } }) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();

  if (!user || user.role !== "superadmin") {
    throw new ConvexError({ message: "Forbidden: SuperAdmin only", code: "FORBIDDEN" });
  }
  return user;
}

export const listAllUsers = query({
  args: {
    paginationOpts: v.object({ numItems: v.number(), cursor: v.union(v.string(), v.null()) }),
    roleFilter: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const caller = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();

    if (!caller || caller.role !== "superadmin") {
      throw new ConvexError({ message: "Forbidden", code: "FORBIDDEN" });
    }

    if (args.roleFilter && args.roleFilter !== "all") {
      return await ctx.db
        .query("users")
        .withIndex("by_role", (q) => q.eq("role", args.roleFilter!))
        .paginate(args.paginationOpts);
    }

    return await ctx.db.query("users").paginate(args.paginationOpts);
  },
});

// List users suitable as company owners (for admin create-company picker)
export const listUsersForOwnerPicker = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return [];
    const caller = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!caller || caller.role !== "superadmin") return [];

    // Return all users (admin can assign any user as owner)
    const users = await ctx.db.query("users").take(200);
    return users.map((u) => ({
      _id: u._id,
      name: u.name,
      email: u.email,
      role: u.role,
    }));
  },
});

export const setUserRole = mutation({
  args: {
    userId: v.id("users"),
    role: v.string(),
    companyId: v.optional(v.id("companies")),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const caller = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();

    if (!caller || caller.role !== "superadmin") {
      throw new ConvexError({ message: "Forbidden", code: "FORBIDDEN" });
    }

    const validRoles = ["traveler", "owner", "seller", "superadmin"];
    if (!validRoles.includes(args.role)) {
      throw new ConvexError({ message: "Invalid role", code: "BAD_REQUEST" });
    }

    const target = await ctx.db.get(args.userId);
    if (!target) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    await ctx.db.patch(args.userId, {
      role: args.role,
      companyId: args.role === "seller" ? args.companyId : undefined,
    });
  },
});

export const markOnboarded = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();

    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    await ctx.db.patch(user._id, { onboardingCompleted: true });
  },
});
