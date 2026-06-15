export const SELLER_MANUAL_ROLES = ["vendeur", "vendeur_independant"] as const;

export function hasSellerManualAccess(roles: readonly string[]): boolean {
  return SELLER_MANUAL_ROLES.some((role) => roles.includes(role));
}

/** Profil vendeur pur : pas owner ni admin plateforme. */
export function isSellerOnlyManualProfile(
  roles: readonly string[],
  isSuperAdmin: boolean,
): boolean {
  if (!hasSellerManualAccess(roles)) return false;
  if (isSuperAdmin) return false;
  if (roles.includes("owner") || roles.includes("admin_pays")) return false;
  return true;
}
