import type { User } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";

function splitName(fullName: string | undefined) {
  const parts = (fullName ?? "").trim().split(/\s+/).filter(Boolean);
  return {
    firstName: parts[0] ?? "Utilisateur",
    lastName: parts.slice(1).join(" ") || "Tibus",
  };
}

function buildUsername(email: string, userId: string) {
  const base = email.split("@")[0]?.replace(/[^a-zA-Z0-9_]/g, "_") ?? "user";
  return `${base}_${userId.slice(0, 6)}`.toLowerCase();
}

export async function ensureUserProfile(authUser: User) {
  const { data: existing, error: existingError } = await supabase
    .from("Users")
    .select("id")
    .eq("auth_user_id", authUser.id)
    .maybeSingle();

  if (existingError) throw existingError;
  if (existing) return existing.id as string;

  const { data: countries, error: countriesError } = await supabase
    .from("Countries")
    .select("id")
    .limit(1);

  if (countriesError) throw countriesError;
  if (!countries?.length) {
    throw new Error(
      "Aucun pays en base. Ajoutez au moins un pays dans Supabase avant l'inscription.",
    );
  }

  const meta = authUser.user_metadata ?? {};
  const { firstName, lastName } = splitName(
    meta.full_name ?? meta.name ?? undefined,
  );
  const email = authUser.email ?? "";
  const username = buildUsername(email || authUser.id, authUser.id);

  const { data: profile, error: profileError } = await supabase
    .from("Users")
    .insert({
      auth_user_id: authUser.id,
      firstName,
      lastName,
      username,
      email: email || null,
      countryId: countries[0].id,
    })
    .select("id")
    .single();

  if (profileError) throw profileError;

  const { data: travelerRole, error: roleError } = await supabase
    .from("Role")
    .select("id")
    .eq("name", "traveler")
    .single();

  if (roleError) throw roleError;

  const { error: userRoleError } = await supabase.from("UserRoles").insert({
    userId: profile.id,
    roleId: travelerRole.id,
    companyId: null,
    countryId: null,
  });

  if (userRoleError) throw userRoleError;

  return profile.id as string;
}
