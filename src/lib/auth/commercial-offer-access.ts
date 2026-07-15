/** Offre commerciale Word — réservée super_admin et admin_pays uniquement. */
export function canAccessCommercialOffer(
  roles: readonly string[],
  isSuperAdmin: boolean,
): boolean {
  if (isSuperAdmin) return true;
  return roles.includes("admin_pays");
}

/**
 * Modules commerciaux par compagnie — super_admin, propriétaire de la
 * compagnie, ou admin_pays du pays de la compagnie. Ces deux derniers cas
 * nécessitent en plus le droit "manage_feature_modules" (Role.droits,
 * modifiable par le super_admin depuis l'écran Rôles & Permissions — voir
 * has_company_droit() côté base, dont ceci est le miroir front).
 */
export function canManageCompanyFeatureModules(
  roles: readonly string[],
  isSuperAdmin: boolean,
  companyId: string,
  ownedCompanyIds: readonly string[],
  hasDroit: (droit: string) => boolean,
  companyCountryId?: string | null,
  adminPaysCountryIds?: readonly string[],
): boolean {
  if (isSuperAdmin) return true;
  if (!hasDroit("manage_feature_modules")) return false;
  if (roles.includes("owner") && ownedCompanyIds.includes(companyId)) return true;
  if (
    roles.includes("admin_pays") &&
    companyCountryId &&
    (adminPaysCountryIds ?? []).includes(companyCountryId)
  ) {
    return true;
  }
  return false;
}

export const COMMERCIAL_OFFER_EXPORT_BASENAME = "offre-commerciale-tibus";
