export type OnboardingAudience = "traveler" | "owner" | "seller" | "company_staff";

const OWNER_ROLES = new Set(["owner", "super_admin"]);

const COMPANY_STAFF_ROLES = new Set(["comptable_compagnie", "controleur"]);

const SELLER_ROLES = new Set([
  "vendeur",
  "vendeur_independant",
  "vendeur_reseau",
  "vendeur_master",
]);

export function getOnboardingAudience(roles: readonly string[]): OnboardingAudience {
  if (roles.some((role) => OWNER_ROLES.has(role))) return "owner";
  if (roles.some((role) => COMPANY_STAFF_ROLES.has(role))) return "company_staff";
  if (roles.some((role) => SELLER_ROLES.has(role))) return "seller";
  return "traveler";
}
