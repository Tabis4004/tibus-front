import { supabase } from "@/lib/supabase";

export type CompleteProfileInput = {
  userId: string;
  fullName: string;
  username: string;
  phone?: string;
  email?: string;
  countryId: string;
};

function splitName(fullName: string) {
  const parts = fullName.trim().split(/\s+/).filter(Boolean);
  return {
    firstName: parts[0] ?? "Utilisateur",
    lastName: parts.slice(1).join(" ") || "Tibus",
  };
}

export async function completeUserProfile(input: CompleteProfileInput) {
  const username = input.username.trim().toLowerCase();
  const phone = input.phone?.trim() ?? "";
  const { firstName, lastName } = splitName(input.fullName);

  const { data: existingUsername, error: usernameError } = await supabase
    .from("Users")
    .select("id")
    .eq("username", username)
    .maybeSingle();

  if (usernameError) throw usernameError;
  if (existingUsername && existingUsername.id !== input.userId) {
    throw new Error("Username already taken");
  }

  const { data: country, error: countryError } = await supabase
    .from("Countries")
    .select("id")
    .eq("id", input.countryId)
    .maybeSingle();

  if (countryError) throw countryError;
  if (!country) {
    throw new Error("Country not found");
  }

  const { error: updateError } = await supabase
    .from("Users")
    .update({
      firstName,
      lastName,
      username,
      phone: phone || null,
      email: input.email?.trim() || null,
      countryId: input.countryId,
      profileCompleted: true,
    })
    .eq("id", input.userId);

  if (updateError) throw updateError;
}
