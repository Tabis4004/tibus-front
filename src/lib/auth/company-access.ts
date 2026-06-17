export function isDemarcheurRole(roles: readonly string[]): boolean {
  return roles.includes("demarcheur");
}

export function isAdminPaysRole(roles: readonly string[]): boolean {
  return roles.includes("admin_pays");
}

/** Accès au panneau admin plateforme (lecture / commissions), hors console owner. */
export function canAccessPlatformAdminPanel(
  roles: readonly string[],
  isSuperAdmin: boolean,
): boolean {
  if (isSuperAdmin) return true;
  return isAdminPaysRole(roles) || isDemarcheurRole(roles);
}

/** Création ou modification des données opérationnelles d'une compagnie (modules, fiche, console owner). */
export function canMutateCompanyOperationalData(
  roles: readonly string[],
  isSuperAdmin: boolean,
  companyId: string,
  ownedCompanyIds: readonly string[],
): boolean {
  if (isSuperAdmin) return true;
  return roles.includes("owner") && ownedCompanyIds.includes(companyId);
}

export function userOwnsCompany(
  companyId: string,
  ownedCompanyIds: readonly string[],
): boolean {
  return ownedCompanyIds.includes(companyId);
}
