/** Rôles compagnie que le propriétaire peut créer ou attribuer. */
export const OWNER_ASSIGNABLE_TEAM_ROLES = [
  "vendeur",
  "chauffeur",
  "controleur",
  "comptable_compagnie",
  "gestionnaire_gare",
  "gerant_gare",
] as const;

export type OwnerAssignableTeamRole = (typeof OWNER_ASSIGNABLE_TEAM_ROLES)[number];

/** Rôles rattachés à une gare (UserRoles.gareId obligatoire). */
export const GARE_TEAM_ASSIGNABLE_ROLES = [
  "vendeur_gare",
  "controleur_gare",
  "comptable_gare",
] as const;

export type GareTeamAssignableRole = (typeof GARE_TEAM_ASSIGNABLE_ROLES)[number];

export const GARE_MANAGER_ROLE_NAMES = ["gerant_gare", "gestionnaire_gare"] as const;

export function isGareManagerRole(role: string): boolean {
  return (GARE_MANAGER_ROLE_NAMES as readonly string[]).includes(role);
}

export function isOwnerAssignableTeamRole(role: string): role is OwnerAssignableTeamRole {
  return (OWNER_ASSIGNABLE_TEAM_ROLES as readonly string[]).includes(role);
}

export function isGareTeamAssignableRole(role: string): role is GareTeamAssignableRole {
  return (GARE_TEAM_ASSIGNABLE_ROLES as readonly string[]).includes(role);
}
