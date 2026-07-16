import { supabase } from "@/lib/supabase";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

import {
  OWNER_ASSIGNABLE_TEAM_ROLES,
  type OwnerAssignableTeamRole,
} from "@/lib/owner-team-roles.ts";
import { formatAdminPaysTakenMessage, type CountryAdminPaysHolder } from "@/lib/auth/admin-pays-assign.ts";

export const OWNER_TEAM_ROLES = OWNER_ASSIGNABLE_TEAM_ROLES;
export type OwnerTeamRole = OwnerAssignableTeamRole;

export type ProvisionUserInput = {
  firstName: string;
  lastName: string;
  email: string;
  phone?: string;
  password: string;
  roles: string[];
  companyId?: string;
  countryId?: string;
};

export type ProvisionUserResult = {
  success: boolean;
  user: {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
  };
  roles: string[];
};

export type UserRoleAssignment = {
  roleName: string;
  companyId: string | null;
  countryId: string | null;
};

async function getAccessToken(): Promise<string> {
  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session?.access_token) {
    throw new Error("Connectez-vous pour continuer");
  }
  return data.session.access_token;
}

async function invokeFunction<T>(name: string, body: unknown): Promise<T> {
  const accessToken = await getAccessToken();
  const response = await fetch(`${supabaseUrl}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      apikey: supabaseAnonKey,
    },
    body: JSON.stringify(body),
  });

  const raw = await response.text();
  let payload = {} as T & { error?: string };
  try {
    payload = raw ? (JSON.parse(raw) as T & { error?: string }) : ({} as T & { error?: string });
  } catch {
    if (!response.ok) {
      if (response.status === 404) {
        throw new Error(
          `Fonction ${name} introuvable — déployez-la : supabase functions deploy ${name}`,
        );
      }
      throw new Error(raw || `Erreur ${name} (${response.status})`);
    }
  }
  if (!response.ok) {
    throw new Error(payload?.error ?? (raw || `Erreur ${name} (${response.status})`));
  }
  return payload;
}

async function readFunctionError(error: { message?: string; context?: Response }): Promise<string> {
  const ctx = error.context;
  if (ctx) {
    try {
      const payload = (await ctx.json()) as { error?: string };
      if (payload?.error?.trim()) return payload.error;
    } catch {
      // ignore parse errors
    }
  }
  return error.message?.trim() || "Impossible de créer le membre";
}

export async function provisionUserSupabase(
  input: ProvisionUserInput,
): Promise<ProvisionUserResult> {
  const { data, error } = await supabase.functions.invoke("admin-provision-user", {
    body: input,
  });

  if (error) {
    throw new Error(await readFunctionError(error as { message?: string; context?: Response }));
  }

  if (data && typeof data === "object" && "error" in data) {
    const message = String((data as { error?: string }).error ?? "").trim();
    if (message) throw new Error(message);
  }

  if (data && typeof data === "object" && "success" in data) {
    return data as ProvisionUserResult;
  }

  return invokeFunction<ProvisionUserResult>("admin-provision-user", input);
}

/** Création équipe owner : privilégie l'assignation RPC si l'email existe déjà. */
export async function provisionOwnerTeamMemberSupabase(
  input: ProvisionUserInput & { roleName: OwnerTeamRole },
): Promise<ProvisionUserResult> {
  const { assignCompanySellerByEmailSupabase } = await import(
    "@/lib/supabase/owner-operations.ts"
  );

  try {
    return await provisionUserSupabase(input);
  } catch (createErr) {
    const message = createErr instanceof Error ? createErr.message : "";
    const emailTaken = /existe déjà|already|exists|registered|409/i.test(message);
    if (!emailTaken || !input.companyId) throw createErr;

    const assigned = await assignCompanySellerByEmailSupabase({
      email: input.email,
      roleName: input.roleName,
      companyId: input.companyId,
    });

    return {
      success: true,
      user: {
        id: assigned.id,
        firstName: input.firstName,
        lastName: input.lastName,
        email: assigned.email ?? input.email,
      },
      roles: [input.roleName, "traveler"],
    };
  }
}

export async function assignCompanyRoleByEmailSupabase(input: {
  email: string;
  roleName: OwnerTeamRole;
}) {
  const { data, error } = await supabase.rpc("assign_company_user_role_by_email", {
    p_email: input.email.trim().toLowerCase(),
    p_role_name: input.roleName,
  });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) throw new Error("Utilisateur introuvable");
  return row as {
    id: string;
    firstName: string;
    lastName: string;
    email: string | null;
  };
}

export async function removeCompanyRoleSupabase(input: {
  userId: string;
  roleName: OwnerTeamRole;
}) {
  const { error } = await supabase.rpc("remove_company_user_role", {
    p_user_id: input.userId,
    p_role_name: input.roleName,
  });
  if (error) throw error;
}

export async function getCountryAdminPaysHolderSupabase(
  countryId: string,
  excludeUserId?: string | null,
): Promise<CountryAdminPaysHolder | null> {
  const { data, error } = await supabase.rpc("get_country_admin_pays_holder", {
    p_country_id: countryId,
    p_exclude_user_id: excludeUserId ?? null,
  });
  if (error) throw error;

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null;

  const payload = row as Record<string, unknown>;
  const userId = String(payload.user_id ?? payload.userId ?? "");
  if (!userId) return null;

  return {
    userId,
    fullName: payload.full_name ? String(payload.full_name) : payload.fullName ? String(payload.fullName) : null,
    email: payload.email ? String(payload.email) : null,
  };
}

export async function assertCountryAdminPaysAvailable(
  countryId: string,
  options?: { excludeUserId?: string | null; countryLabel?: string },
): Promise<void> {
  const holder = await getCountryAdminPaysHolderSupabase(countryId, options?.excludeUserId);
  if (!holder) return;

  throw new Error(formatAdminPaysTakenMessage(holder, options?.countryLabel));
}

export async function adminAssignUserRoleSupabase(input: {
  userId: string;
  roleName: string;
  companyId?: string | null;
  countryId?: string | null;
}) {
  const { error } = await supabase.rpc("admin_assign_user_role", {
    p_user_id: input.userId,
    p_role_name: input.roleName,
    p_company_id: input.companyId ?? null,
    p_country_id: input.countryId ?? null,
  });
  if (error) throw error;
}

export async function adminRemoveUserRoleSupabase(input: {
  userId: string;
  roleName: string;
  companyId?: string | null;
  countryId?: string | null;
}) {
  const { error } = await supabase.rpc("admin_remove_user_role", {
    p_user_id: input.userId,
    p_role_name: input.roleName,
    p_company_id: input.companyId ?? null,
    p_country_id: input.countryId ?? null,
  });
  if (error) throw error;
}

export async function listUserRoleAssignmentsSupabase(
  userId: string,
): Promise<UserRoleAssignment[]> {
  const { data, error } = await supabase
    .from("UserRoles")
    .select("companyId, countryId, Role(name)")
    .eq("userId", userId);

  if (error) throw error;

  return (data ?? []).map((row) => {
    const role = Array.isArray(row.Role) ? row.Role[0] : row.Role;
    return {
      roleName: (role as { name: string } | null)?.name ?? "",
      companyId: (row.companyId as string | null) ?? null,
      countryId: (row.countryId as string | null) ?? null,
    };
  }).filter((r) => r.roleName);
}

export function roleAssignmentKey(role: UserRoleAssignment) {
  return `${role.roleName}:${role.companyId ?? ""}:${role.countryId ?? ""}`;
}

export function isCompanyScopedRole(roleName: string) {
  return ["owner", "vendeur", "chauffeur", "controleur", "comptable_compagnie"].includes(roleName);
}

/** Réservé au super_admin (vérifié aussi côté Edge Function) : définit
 * directement le mot de passe d'un utilisateur, sans passer par le flux
 * "mot de passe oublié" — utile quand l'utilisateur n'a pas accès à sa
 * boîte mail ou son téléphone. */
export async function adminResetUserPasswordSupabase(input: {
  userId: string;
  newPassword: string;
}): Promise<void> {
  const { data, error } = await supabase.functions.invoke("admin-reset-password", {
    body: input,
  });

  if (error) {
    throw new Error(await readFunctionError(error as { message?: string; context?: Response }));
  }

  if (data && typeof data === "object" && "error" in data) {
    const message = String((data as { error?: string }).error ?? "").trim();
    if (message) throw new Error(message);
  }
}
