export const ESTABLISHED_PRO_ROLES = [
  "super_admin",
  "admin_pays",
  "demarcheur",
  "owner",
  "vendeur",
  "chauffeur",
  "vendeur_master",
  "vendeur_reseau",
  "vendeur_independant",
  "controleur",
  "comptable_compagnie",
  "gestionnaire_gare",
  "gerant_gare",
  "vendeur_gare",
  "controleur_gare",
  "comptable_gare",
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

const PLACEHOLDER_FIRST_NAME = "Utilisateur";
const PLACEHOLDER_LAST_NAME = "Tibus";

export function isPlaceholderProfileName(
  firstName?: string | null,
  lastName?: string | null,
): boolean {
  const first = firstName?.trim() ?? "";
  const last = lastName?.trim() ?? "";
  return first === PLACEHOLDER_FIRST_NAME && last === PLACEHOLDER_LAST_NAME;
}

export function profileDisplayName(profile: {
  firstName?: string | null;
  lastName?: string | null;
} | null | undefined): string {
  if (!profile) return "";
  const name = `${profile.firstName ?? ""} ${profile.lastName ?? ""}`.trim();
  if (!name || isPlaceholderProfileName(profile.firstName, profile.lastName)) return "";
  return name;
}

export function hasValidProfilePhone(phone?: string | null): boolean {
  return (phone ?? "").replace(/\D/g, "").length >= 9;
}

function hasProvisionedIdentity(profile: NonNullable<ProfileLike>): boolean {
  const hasName =
    Boolean(profile.firstName?.trim()) && Boolean(profile.lastName?.trim());
  const hasUsername = Boolean(profile.username?.trim());
  const hasCountry = Boolean(profile.countryId);
  return hasName && hasUsername && hasCountry;
}

function hasTravelerIdentity(profile: NonNullable<ProfileLike>): boolean {
  const hasName =
    Boolean(profile.firstName?.trim()) &&
    Boolean(profile.lastName?.trim()) &&
    !isPlaceholderProfileName(profile.firstName, profile.lastName);
  return hasName && hasValidProfilePhone(profile.phone);
}

/** Champs requis remplis (voyageur ou pro provisionné). */
export function isProfileComplete(
  profile: ProfileLike,
  roles: readonly string[] = [],
): boolean {
  if (!profile) return false;
  if (hasTravelerIdentity(profile)) return true;
  if (
    roles.some((role) =>
      (ESTABLISHED_PRO_ROLES as readonly string[]).includes(role),
    ) &&
    hasProvisionedIdentity(profile)
  ) {
    return true;
  }
  return false;
}

/** Gate unique : une fois le flag DB à true, on ne redemande plus le formulaire. */
export function hasCompletedProfileOnce(profile: ProfileLike): boolean {
  return Boolean(profile?.profileCompleted);
}

/** Profil éligible au backfill automatique du flag (comptes legacy). */
export function shouldBackfillProfileCompleted(
  profile: ProfileLike,
  roles: readonly string[] = [],
): boolean {
  if (!profile || profile.profileCompleted) return false;
  return isProfileComplete(profile, roles);
}
