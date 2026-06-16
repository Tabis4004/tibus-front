/** Offre commerciale Word — réservée super_admin et admin_pays uniquement. */
export function canAccessCommercialOffer(
  roles: readonly string[],
  isSuperAdmin: boolean,
): boolean {
  if (isSuperAdmin) return true;
  return roles.includes("admin_pays");
}

/** Modules commerciaux par compagnie — même périmètre que l'offre commerciale. */
export function canManageCompanyFeatureModules(
  roles: readonly string[],
  isSuperAdmin: boolean,
): boolean {
  return canAccessCommercialOffer(roles, isSuperAdmin);
}

export const COMMERCIAL_OFFER_FILENAME = "offre-commerciale-tibus.docx";
