import { COMPANY_STAFF_ROLE_NAMES } from "@/lib/supabase/owner-company.ts";

/** Rôles liés à une compagnie — aucune carte réseau Tibus. */
export const COMPANY_GARES_MAP_BLOCK_ROLES = ["owner", ...COMPANY_STAFF_ROLE_NAMES] as const;

export function isCompanyLinkedForGaresMap(roles: readonly string[]): boolean {
  return roles.some((role) =>
    (COMPANY_GARES_MAP_BLOCK_ROLES as readonly string[]).includes(role),
  );
}

/**
 * Carte réseau (toutes les gares) :
 * - visiteurs non connectés : oui (landing publique)
 * - comptes connectés : uniquement le rôle voyageur sans lien compagnie
 */
export function canViewNetworkGaresMap(
  roles: readonly string[],
  isAuthenticated: boolean,
): boolean {
  if (isCompanyLinkedForGaresMap(roles)) return false;
  if (!isAuthenticated) return true;
  return roles.includes("traveler");
}
