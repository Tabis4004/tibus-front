/** Offre commerciale Word — réservée super_admin et admin_pays uniquement. */
export function canAccessCommercialOffer(
  roles: readonly string[],
  isSuperAdmin: boolean,
): boolean {
  if (isSuperAdmin) return true;
  return roles.includes("admin_pays");
}

/** Modules commerciaux par compagnie — propriétaire ou super admin uniquement. */
export function canManageCompanyFeatureModules(
  roles: readonly string[],
  isSuperAdmin: boolean,
  companyId: string,
  ownedCompanyIds: readonly string[],
): boolean {
  if (isSuperAdmin) return true;
  return roles.includes("owner") && ownedCompanyIds.includes(companyId);
}

export const COMMERCIAL_OFFER_EXPORT_BASENAME = "offre-commerciale-tibus";
