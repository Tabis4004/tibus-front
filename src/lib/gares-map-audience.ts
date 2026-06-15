import { COMPANY_STAFF_ROLE_NAMES } from "@/lib/supabase/owner-company.ts";

export type GaresMapScope = "platform" | "company";

/** Utilisateurs liés à une compagnie : carte filtrée à leurs gares uniquement. */
export function resolveGaresMapScope(roles: readonly string[]): GaresMapScope {
  const hasCompanyStaffRole = roles.some((role) =>
    (COMPANY_STAFF_ROLE_NAMES as readonly string[]).includes(role),
  );
  return hasCompanyStaffRole ? "company" : "platform";
}

/** La carte ne doit jamais être intégrée au dashboard / accueil connecté des rôles pro. */
export function shouldShowGaresMapOnDashboard(): boolean {
  return false;
}
