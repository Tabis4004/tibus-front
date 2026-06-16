export function isDemarcheur(roles: readonly string[]): boolean {
  return roles.includes("demarcheur");
}

export function canAccessDemarcheurDashboard(
  roles: readonly string[],
  isSuperAdmin: boolean,
): boolean {
  if (isSuperAdmin) return true;
  return isDemarcheur(roles);
}
