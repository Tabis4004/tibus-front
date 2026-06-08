import { supabase } from "@/lib/supabase";

export async function markOnboardingCompleted(userId: string) {
  const { error } = await supabase
    .from("Users")
    .update({ onboardingCompleted: true })
    .eq("id", userId);

  if (error) throw error;
}
