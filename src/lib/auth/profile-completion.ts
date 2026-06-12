export const ESTABLISHED_PRO_ROLES = [
  "super_admin",
  "admin_pays",
  "owner",
  "vendeur",
  "vendeur_master",
  "vendeur_reseau",
  "vendeur_independant",
  "controleur",
  "comptable_compagnie",
  "gestionnaire_gare",
] as const;

type ProfileLike =
  | {
      profileCompleted?: boolean;
      phone?: string | null;
      firstName?: string | null;
      lastName?: string | null;
      username?: string | null;
      countryId?: string | null;
    }
  | null
  | undefined;

/** Utilisateur authentifié avec une ligne Users — la page complete-profile n'est plus imposée. */
export function isProfileComplete(
  profile: ProfileLike,
  _roles: readonly string[] = [],
): boolean {
  return Boolean(profile);
}
