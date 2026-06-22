import { supabase } from "@/lib/supabase";
import { roleDashboardPath } from "@/lib/gare-role-routing.ts";

function normalizeRoleForUi(role: string): string {
  if (role === "super_admin") return "superadmin";
  return role;
}

/** Priorité écran d'accès après connexion — owner avant admin plateforme. */
const DASHBOARD_ROLE_PRIORITY = [
  "owner",
  "super_admin",
  "admin_pays",
  "demarcheur",
  "master_independant",
  "master",
  "vendeur_master",
  "comptable_compagnie",
  "comptable_gare",
  "controleur",
  "controleur_gare",
  "gerant_gare",
  "gestionnaire_gare",
  "chauffeur",
  "vendeur_gare",
  "vendeur_reseau",
  "vendeur",
  "vendeur_independant",
  "traveler",
] as const;

export function hasOwnerDashboardAccess(roles: readonly string[]): boolean {
  return roles.includes("owner");
}

export function resolveDashboardRole(roles: readonly string[]): string {
  if (hasOwnerDashboardAccess(roles)) return "owner";
  return (
    DASHBOARD_ROLE_PRIORITY.find((role) => roles.includes(role)) ??
    roles[0] ??
    "traveler"
  );
}

export function resolveDashboardRoleUi(roles: readonly string[]): string {
  return normalizeRoleForUi(resolveDashboardRole(roles));
}

export function resolveUserHomePath(lng: string): string {
  return `/${lng || "fr"}`;
}

export function resolveDashboardPath(lng: string, roles: readonly string[]): string {
  const locale = lng || "fr";
  const role = resolveDashboardRole(roles);

  if (role === "owner") return `/${locale}/owner`;
  if (role === "gerant_gare" || role === "gestionnaire_gare") {
    return roleDashboardPath(locale, "gerant_gare");
  }
  if (role === "comptable_gare") return roleDashboardPath(locale, "comptable_gare");
  if (role === "controleur_gare") return roleDashboardPath(locale, "controleur_gare");
  if (role === "super_admin" || role === "admin_pays") return `/${locale}/admin`;
  if (role === "demarcheur") return `/${locale}/admin/demarcheur`;
  if (
    role === "vendeur" ||
    role === "vendeur_gare" ||
    role === "vendeur_independant" ||
    role === "vendeur_reseau" ||
    role === "vendeur_master" ||
    role === "chauffeur"
  ) {
    return `/${locale}/seller`;
  }
  if (role === "comptable_compagnie") return `/${locale}/owner/trips`;
  if (role === "controleur") return roleDashboardPath(locale, "controleur");
  return `/${locale}`;
}

function roleNameFromJoin(
  role: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!role) return null;
  if (Array.isArray(role)) return role[0]?.name ?? null;
  return role.name ?? null;
}

export async function fetchUserRoleNames(userId: string): Promise<string[]> {
  const { data: userRoles, error } = await supabase
    .from("UserRoles")
    .select("Role(name)")
    .eq("userId", userId);

  if (error) throw error;

  return (userRoles ?? [])
    .map((row) =>
      roleNameFromJoin(row.Role as { name: string } | { name: string }[] | null),
    )
    .filter((name): name is string => Boolean(name));
}
