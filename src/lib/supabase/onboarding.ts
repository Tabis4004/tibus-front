import { markOnboardingDismissedLocal } from "@/lib/auth/onboarding-completion.ts";
import { supabase } from "@/lib/supabase";

export async function markOnboardingCompleted(userId: string) {
  markOnboardingDismissedLocal(userId);

  const { data, error } = await supabase
    .from("Users")
    .update({ onboardingCompleted: true })
    .eq("id", userId)
    .select("id")
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    throw new Error("Impossible d'enregistrer la fin du guide (profil introuvable ou droits insuffisants)");
  }
}
