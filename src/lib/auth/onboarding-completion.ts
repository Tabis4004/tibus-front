import { isProfileComplete } from "@/lib/auth/profile-completion.ts";

const DISMISSED_PREFIX = "tibus:onboarding-dismissed:";

const ESTABLISHED_PRO_ROLES = [
  "super_admin",
  "admin_pays",
  "owner",
  "vendeur",
  "vendeur_master",
  "vendeur_reseau",
  "vendeur_independant",
  "controleur",
  "comptable_compagnie",
] as const;

export function onboardingDismissedStorageKey(userId: string) {
  return `${DISMISSED_PREFIX}${userId}`;
}

/** DB, localStorage, ou compte pro déjà renseigné (évite le guide à chaque login). */
export function hasCompletedOnboarding(
  profile: { onboardingCompleted?: boolean; phone?: string | null; profileCompleted?: boolean } | null | undefined,
  userId: string | null | undefined,
  roles: readonly string[] = [],
): boolean {
  if (profile?.onboardingCompleted) return true;
  if (!userId) return false;
  try {
    if (localStorage.getItem(onboardingDismissedStorageKey(userId)) === "1") return true;
  } catch {
    // quota / mode privé
  }
  if (
    isProfileComplete(profile) &&
    roles.some((role) => (ESTABLISHED_PRO_ROLES as readonly string[]).includes(role))
  ) {
    return true;
  }
  return false;
}

export function markOnboardingDismissedLocal(userId: string) {
  try {
    localStorage.setItem(onboardingDismissedStorageKey(userId), "1");
  } catch {
    // quota / mode privé
  }
}
