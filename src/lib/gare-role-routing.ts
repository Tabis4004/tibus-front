import {
  hasGareComptableDashboardAccess,
  hasGareControleurScanAccess,
  hasGareManagerDashboardAccess,
  isGareManagerRole,
} from "@/lib/owner-team-roles.ts";

/** Chemins dashboard dédiés par rôle métier (suffixe sans locale). */
export const ROLE_DASHBOARD_SUFFIX = {
  controleur: "/owner/controleur",
  controleur_gare: "/owner/gare/controleur",
  gerant_gare: "/owner/gare/gerant",
  gestionnaire_gare: "/owner/gare/gerant",
  comptable_gare: "/owner/gare/comptable",
  vendeur_gare: "/seller",
  vendeur: "/seller",
  chauffeur: "/seller",
} as const;

export type RoleDashboardKey = keyof typeof ROLE_DASHBOARD_SUFFIX;

export function roleDashboardPath(lng: string, role: RoleDashboardKey): string {
  const locale = lng || "fr";
  return `/${locale}${ROLE_DASHBOARD_SUFFIX[role]}`;
}

/** Dashboard gare prioritaire pour un staff gare sans rôle owner/compagnie. */
export function resolvePrimaryGareStaffDashboardPath(
  lng: string,
  roles: readonly string[],
): string {
  if (roles.some((role) => isGareManagerRole(role))) {
    return roleDashboardPath(lng, "gerant_gare");
  }
  if (roles.includes("comptable_gare")) {
    return roleDashboardPath(lng, "comptable_gare");
  }
  if (roles.includes("controleur_gare")) {
    return roleDashboardPath(lng, "controleur_gare");
  }
  // chef_embarqueur : ni gérant, ni comptable, ni contrôleur — pas de
  // dashboard dédié (il ne voit aucune donnée d'argent). Avant ce cas, on
  // retombait sur "gerant_gare" par défaut, dont GareDashboardPage refuse
  // ensuite l'accès (canAccessVariant exige isGareManagerRole) : impasse.
  if (roles.includes("chef_embarqueur")) {
    const locale = lng || "fr";
    return `/${locale}/owner`;
  }
  return roleDashboardPath(lng, "gerant_gare");
}

export function resolveGareBottomNavDashboardPath(lng: string, roles: readonly string[]): string {
  if (hasGareManagerDashboardAccess(roles)) {
    return roleDashboardPath(lng, "gerant_gare");
  }
  if (hasGareComptableDashboardAccess(roles)) {
    return roleDashboardPath(lng, "comptable_gare");
  }
  if (hasGareControleurScanAccess(roles)) {
    return roleDashboardPath(lng, "controleur_gare");
  }
  return resolvePrimaryGareStaffDashboardPath(lng, roles);
}
