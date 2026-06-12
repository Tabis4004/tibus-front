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

/** Nom complet + téléphone requis pour les voyageurs. */
export function isProfileComplete(
  profile: ProfileLike,
  roles: readonly string[] = [],
): boolean {
  if (!profile) return false;
  if (profile.profileCompleted) return true;
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
