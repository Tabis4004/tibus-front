/** Aligné sur 006_profile_completion.sql : téléphone renseigné = profil complet. */
export function isProfileComplete(
  profile:
    | { profileCompleted?: boolean; phone?: string | null }
    | null
    | undefined,
): boolean {
  if (!profile) return false;
  if (profile.profileCompleted) return true;
  return Boolean(profile.phone?.trim());
}
