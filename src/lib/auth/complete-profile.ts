import { supabase } from "@/lib/supabase";
import { hasValidProfilePhone } from "@/lib/auth/profile-completion.ts";

export type CompleteProfileInput = {
  userId: string;
  fullName: string;
  username: string;
  phone: string;
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
  const phone = input.phone.trim();
  if (!hasValidProfilePhone(phone)) {
    throw new Error("Phone number is required");
  }
  const { firstName, lastName } = splitName(input.fullName);

  const { data: existingUsername, error: usernameError } = await supabase
    .from("users")
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
    .from("users")
    .update({
      firstName,
      lastName,
      username,
      phone,
      email: input.email?.trim() || null,
      countryId: input.countryId,
      profileCompleted: true,
    })
    .eq("id", input.userId);

  if (updateError) throw updateError;
}

export type SignupProfileInput = {
  userId: string;
  email: string;
  fullName: string;
  phone: string;
};

function buildUsername(email: string, userId: string) {
  const base = email.split("@")[0]?.replace(/[^a-zA-Z0-9_]/g, "_") ?? "user";
  return `${base}_${userId.slice(0, 6)}`.toLowerCase();
}

export async function applySignupProfile(input: SignupProfileInput): Promise<void> {
  const phone = input.phone.trim();
  if (!hasValidProfilePhone(phone)) {
    throw new Error("Phone number is required");
  }

  const { firstName, lastName } = splitName(input.fullName);
  const username = buildUsername(input.email, input.userId);

  const { error } = await supabase
    .from("users")
    .update({
      firstName,
      lastName,
      phone,
      username,
      email: input.email.trim() || null,
      profileCompleted: true,
    })
    .eq("id", input.userId);

  if (error) throw error;
}
