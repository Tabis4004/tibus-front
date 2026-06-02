import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";

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

// ─── Available permissions ────────────────────────────────────────────────────
// This is the master list of all possible permissions in the system.
// SuperAdmin picks from these when creating/editing a role.
export const AVAILABLE_PERMISSIONS = [
  "manage_company",
  "manage_buses",
  "manage_stations",
  "manage_routes",
  "manage_trips",
  "sell_tickets",
  "reserve_tickets",
  "view_bookings",
  "cancel_bookings",
  "manage_sellers",
  "view_reports",
  "manage_subscriptions",
] as const;

// ─── Built-in Role Permissions ────────────────────────────────────────────────
// These are the default permissions for the built-in roles (owner, seller, traveler).
// SuperAdmin can override them using the rolePermissions table.

const DEFAULT_BUILTIN_PERMS: Record<string, string[]> = {
  owner: [
    "manage_company",
    "manage_buses",
    "manage_stations",
    "manage_routes",
    "manage_trips",
    "sell_tickets",
    "view_bookings",
    "cancel_bookings",
    "manage_sellers",
    "view_reports",
    "manage_subscriptions",
  ],
  seller: ["sell_tickets", "view_bookings"],
  traveler: ["reserve_tickets", "view_bookings"],
};

export const getBuiltinRolePermissions = query({
  args: {},
  handler: async (ctx) => {
    await requireAdmin(ctx);
    const builtinRoles = ["owner", "seller", "traveler"];
    const result: { role: string; permissions: string[] }[] = [];

    for (const role of builtinRoles) {
      // Check if there's a custom override in rolePermissions table
      const override = await ctx.db
        .query("rolePermissions")
        .withIndex("by_role", (q) => q.eq("role", role))
        .first();

      result.push({
        role,
        permissions: override ? override.permissions : (DEFAULT_BUILTIN_PERMS[role] ?? []),
      });
    }
    return result;
  },
});

export const setBuiltinRolePermissions = mutation({
  args: {
    role: v.string(),
    permissions: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);

    // Only allow editing built-in roles
    if (!["owner", "seller", "traveler"].includes(args.role)) {
      throw new ConvexError({ message: "Can only edit built-in roles", code: "BAD_REQUEST" });
    }

    // Check if override already exists
    const existing = await ctx.db
      .query("rolePermissions")
      .withIndex("by_role", (q) => q.eq("role", args.role))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        permissions: args.permissions,
        updatedBy: admin._id,
      });
    } else {
      await ctx.db.insert("rolePermissions", {
        role: args.role,
        permissions: args.permissions,
        updatedBy: admin._id,
      });
    }
  },
});

// ─── Roles CRUD ───────────────────────────────────────────────────────────────

export const listRoles = query({
  args: {},
  handler: async (ctx) => {
    await requireAdmin(ctx);
    return await ctx.db.query("roles").collect();
  },
});

export const getAvailablePermissions = query({
  args: {},
  handler: async (ctx) => {
    await requireAdmin(ctx);
    return [...AVAILABLE_PERMISSIONS];
  },
});

export const createRole = mutation({
  args: {
    name: v.string(),
    permissions: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const trimmed = args.name.trim();
    if (!trimmed) throw new ConvexError({ message: "Role name is required", code: "BAD_REQUEST" });

    // Check for duplicate name
    const existing = await ctx.db
      .query("roles")
      .withIndex("by_name", (q) => q.eq("name", trimmed))
      .first();
    if (existing) throw new ConvexError({ message: "A role with this name already exists", code: "CONFLICT" });

    return await ctx.db.insert("roles", {
      name: trimmed,
      permissions: args.permissions,
    });
  },
});

export const updateRole = mutation({
  args: {
    roleId: v.id("roles"),
    name: v.optional(v.string()),
    permissions: v.optional(v.array(v.string())),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const role = await ctx.db.get(args.roleId);
    if (!role) throw new ConvexError({ message: "Role not found", code: "NOT_FOUND" });

    const patch: Record<string, unknown> = {};
    if (args.name !== undefined) {
      const trimmed = args.name.trim();
      if (!trimmed) throw new ConvexError({ message: "Role name is required", code: "BAD_REQUEST" });
      // Check duplicate if name changed
      if (trimmed !== role.name) {
        const dup = await ctx.db
          .query("roles")
          .withIndex("by_name", (q) => q.eq("name", trimmed))
          .first();
        if (dup) throw new ConvexError({ message: "A role with this name already exists", code: "CONFLICT" });
      }
      patch.name = trimmed;
    }
    if (args.permissions !== undefined) {
      patch.permissions = args.permissions;
    }
    await ctx.db.patch(args.roleId, patch);
  },
});

export const deleteRole = mutation({
  args: { roleId: v.id("roles") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const role = await ctx.db.get(args.roleId);
    if (!role) throw new ConvexError({ message: "Role not found", code: "NOT_FOUND" });

    // Remove all user-role assignments for this role
    const assignments = await ctx.db
      .query("userRoles")
      .withIndex("by_role", (q) => q.eq("roleId", args.roleId))
      .collect();
    for (const a of assignments) {
      await ctx.db.delete(a._id);
    }

    await ctx.db.delete(args.roleId);
  },
});

// ─── User-Role Assignments ──────────────────────────────────────────────────

export const listUserRoles = query({
  args: { userId: v.optional(v.id("users")) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    if (args.userId) {
      const assignments = await ctx.db
        .query("userRoles")
        .withIndex("by_user", (q) => q.eq("userId", args.userId!))
        .collect();
      return await Promise.all(
        assignments.map(async (a) => {
          const role = await ctx.db.get(a.roleId);
          const company = a.companyId ? await ctx.db.get(a.companyId) : null;
          return { ...a, roleName: role?.name ?? "?", companyName: company?.name ?? null };
        }),
      );
    }
    // Return all assignments
    const all = await ctx.db.query("userRoles").collect();
    return await Promise.all(
      all.map(async (a) => {
        const role = await ctx.db.get(a.roleId);
        const company = a.companyId ? await ctx.db.get(a.companyId) : null;
        const user = await ctx.db.get(a.userId);
        return {
          ...a,
          roleName: role?.name ?? "?",
          companyName: company?.name ?? null,
          userName: user?.name ?? user?.email ?? "?",
        };
      }),
    );
  },
});

export const assignUserRole = mutation({
  args: {
    userId: v.id("users"),
    roleId: v.id("roles"),
    companyId: v.optional(v.id("companies")),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);

    const user = await ctx.db.get(args.userId);
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    const role = await ctx.db.get(args.roleId);
    if (!role) throw new ConvexError({ message: "Role not found", code: "NOT_FOUND" });

    // Check for duplicate assignment
    const existing = await ctx.db
      .query("userRoles")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();
    const dup = existing.find(
      (a) => a.roleId === args.roleId && a.companyId === (args.companyId ?? undefined),
    );
    if (dup) throw new ConvexError({ message: "User already has this role", code: "CONFLICT" });

    return await ctx.db.insert("userRoles", {
      userId: args.userId,
      roleId: args.roleId,
      companyId: args.companyId,
    });
  },
});

export const removeUserRole = mutation({
  args: { assignmentId: v.id("userRoles") },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const assignment = await ctx.db.get(args.assignmentId);
    if (!assignment) throw new ConvexError({ message: "Assignment not found", code: "NOT_FOUND" });
    await ctx.db.delete(args.assignmentId);
  },
});
