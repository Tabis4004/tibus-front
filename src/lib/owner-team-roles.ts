/** Rôles compagnie que le propriétaire peut créer ou attribuer (hors gérant — voir Gares).
 *  emballeur_gare / chargeur_gare / distributeur_gare : rôles GLOBAUX à la
 *  compagnie depuis la migration 193 (plus rattachés à une seule gare) —
 *  emballeur et chargeur font le même travail terrain (emballage +
 *  impression du bordereau, puis scan du bordereau pour confirmer le
 *  chargement) et peuvent tous deux faire les deux actions ; le
 *  distributeur reçoit les lots à l'arrivée, sur n'importe quelle gare de
 *  la compagnie. Les trois ont accès à la liste générale des colis (voir
 *  list_colis_autonomes). */
export const OWNER_ASSIGNABLE_TEAM_ROLES = [
  "vendeur",
  "chauffeur",
  "controleur",
  "comptable_compagnie",
  "emballeur_gare",
  "chargeur_gare",
  "distributeur_gare",
] as const;

export type OwnerAssignableTeamRole = (typeof OWNER_ASSIGNABLE_TEAM_ROLES)[number];

/** Rôles rattachés à une gare précise (UserRoles.gareId obligatoire),
 *  assignables depuis l'onglet "Équipe" de la page Gares. */
export const GARE_TEAM_ASSIGNABLE_ROLES = [
  "vendeur_gare",
  "controleur_gare",
  "comptable_gare",
] as const;

export type GareTeamAssignableRole = (typeof GARE_TEAM_ASSIGNABLE_ROLES)[number];

/** Gérant opérationnel (équipe, commissions, départs). */
export const GARE_MANAGER_ROLE_NAME = "gerant_gare" as const;

/** Alias legacy encore présents en base avant migration 147. */
export const GARE_MANAGER_LEGACY_ROLE_NAMES = ["gestionnaire_gare"] as const;

export const GARE_MANAGER_ROLE_NAMES = [
  GARE_MANAGER_ROLE_NAME,
  ...GARE_MANAGER_LEGACY_ROLE_NAMES,
] as const;

export const GARE_DASHBOARD_ROLE_NAMES = [
  GARE_MANAGER_ROLE_NAME,
  ...GARE_MANAGER_LEGACY_ROLE_NAMES,
  "comptable_gare",
] as const;

export const GARE_CONSOLE_ACCESS_ROLE_NAMES = [
  ...GARE_DASHBOARD_ROLE_NAMES,
  "controleur_gare",
] as const;

export const GARE_CASH_VALIDATOR_ROLE_NAMES = [
  "comptable_gare",
  GARE_MANAGER_ROLE_NAME,
  ...GARE_MANAGER_LEGACY_ROLE_NAMES,
] as const;

export function isGareCashValidatorRole(role: string): boolean {
  return (GARE_CASH_VALIDATOR_ROLE_NAMES as readonly string[]).includes(role);
}

export function isGareManagerRole(role: string): boolean {
  return (GARE_MANAGER_ROLE_NAMES as readonly string[]).includes(role);
}

export function isOwnerAssignableTeamRole(role: string): role is OwnerAssignableTeamRole {
  return (OWNER_ASSIGNABLE_TEAM_ROLES as readonly string[]).includes(role);
}

export function isGareTeamAssignableRole(role: string): role is GareTeamAssignableRole {
  return (GARE_TEAM_ASSIGNABLE_ROLES as readonly string[]).includes(role);
}

export function hasGareDashboardAccess(roles: readonly string[]): boolean {
  return roles.some((role) =>
    (GARE_DASHBOARD_ROLE_NAMES as readonly string[]).includes(role),
  );
}

export function hasGareConsoleAccess(roles: readonly string[]): boolean {
  return roles.some((role) =>
    (GARE_CONSOLE_ACCESS_ROLE_NAMES as readonly string[]).includes(role),
  );
}

export function isGareStaffOnlyConsoleUser(roles: readonly string[]): boolean {
  if (!hasGareConsoleAccess(roles)) return false;
  return !roles.some((role) =>
    ["owner", "super_admin", "comptable_compagnie", "controleur"].includes(role),
  );
}

export function canOpenStationCashRegister(roles: readonly string[]): boolean {
  return roles.some((role) =>
    ["vendeur", "vendeur_gare", "chauffeur"].includes(role),
  );
}

export function hasGareManagerDashboardAccess(roles: readonly string[]): boolean {
  return roles.some((role) => isGareManagerRole(role));
}

export function hasGareComptableDashboardAccess(roles: readonly string[]): boolean {
  return roles.includes("comptable_gare");
}

export function hasGareControleurScanAccess(roles: readonly string[]): boolean {
  return roles.includes("controleur_gare");
}

export function hasCompanyControleurScanAccess(roles: readonly string[]): boolean {
  return roles.includes("controleur");
}
