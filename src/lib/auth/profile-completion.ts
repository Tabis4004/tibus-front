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

function hasProvisionedIdentity(profile: NonNullable<ProfileLike>): boolean {
  const hasName =
    Boolean(profile.firstName?.trim()) && Boolean(profile.lastName?.trim());
  const hasUsername = Boolean(profile.username?.trim());
  const hasCountry = Boolean(profile.countryId);
  return hasName && hasUsername && hasCountry;
}

/** Aligné sur 006_profile_completion.sql : téléphone ou compte pro provisionné. */
export function isProfileComplete(
  profile: ProfileLike,
  roles: readonly string[] = [],
): boolean {
  if (!profile) return false;
  if (profile.profileCompleted) return true;
  if (profile.phone?.trim()) return true;
  if (
    roles.some((role) =>
      (ESTABLISHED_PRO_ROLES as readonly string[]).includes(role),
    )
    && hasProvisionedIdentity(profile)
  ) {
    return true;
  }
  return false;
}
