/** Rôles compagnie que le propriétaire peut créer ou attribuer. */
export const OWNER_ASSIGNABLE_TEAM_ROLES = [
  "vendeur",
  "chauffeur",
  "controleur",
  "comptable_compagnie",
  "gestionnaire_gare",
] as const;

export type OwnerAssignableTeamRole = (typeof OWNER_ASSIGNABLE_TEAM_ROLES)[number];

export function isOwnerAssignableTeamRole(role: string): role is OwnerAssignableTeamRole {
  return (OWNER_ASSIGNABLE_TEAM_ROLES as readonly string[]).includes(role);
}
