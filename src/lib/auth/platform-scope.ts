const PLATFORM_SCOPE_ROLES = [
  "super_admin",
  "admin_pays",
  "master",
  "master_independant",
  "vendeur_master",
  "vendeur_independant",
] as const;

export function hasPlatformScope(roles: readonly string[], isSuperAdmin: boolean): boolean {
  if (isSuperAdmin) return true;
  return roles.some((role) =>
    PLATFORM_SCOPE_ROLES.includes(role as (typeof PLATFORM_SCOPE_ROLES)[number]),
  );
}
