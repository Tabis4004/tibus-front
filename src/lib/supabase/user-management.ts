import { supabase } from "@/lib/supabase";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

export const OWNER_TEAM_ROLES = [
  "vendeur",
  "comptable_compagnie",
  "controleur",
] as const;

export type OwnerTeamRole = (typeof OWNER_TEAM_ROLES)[number];

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

export async function provisionUserSupabase(
  input: ProvisionUserInput,
): Promise<ProvisionUserResult> {
  return invokeFunction<ProvisionUserResult>("admin-provision-user", input);
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
  return ["owner", "vendeur", "controleur", "comptable_compagnie"].includes(roleName);
}
