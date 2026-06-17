import {
  canAccessPlatformAdminPanel,
  isDemarcheurRole,
} from "@/lib/auth/company-access.ts";

export function hasPlatformScope(roles: readonly string[], isSuperAdmin: boolean): boolean {
  return canAccessPlatformAdminPanel(roles, isSuperAdmin);
}

export { isDemarcheurRole };
