import { supabase } from "@/lib/supabase";

export type PlatformAdminUserRow = {
  id: string;
  email: string | null;
  firstName: string;
  lastName: string;
  username: string;
  roles: string[];
};

export async function listPlatformUsersForAdminSupabase(limit = 200, offset = 0) {
  const { data, error } = await supabase.rpc("list_platform_users_for_admin", {
    p_limit: limit,
    p_offset: offset,
  });

  if (error) throw error;

  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: row.id as string,
    email: (row.email as string | null) ?? null,
    firstName: row.firstName as string,
    lastName: row.lastName as string,
    username: row.username as string,
    roles: (row.roles as string[] | null) ?? [],
  })) satisfies PlatformAdminUserRow[];
}

export async function countPlatformUsersForAdminSupabase() {
  const { data, error } = await supabase.rpc("count_platform_users_for_admin");
  if (error) throw error;
  return Number(data ?? 0);
}

// Super_admin uniquement (vérifié côté DB) : accorde/retire des droits sur un
// rôle. Alimente l'écran "Rôles & Permissions" rendu éditable.
export async function updateRoleDroitsSupabase(
  roleName: string,
  droits: string[],
): Promise<{ id: string; name: string; droits: string[] }> {
  const { data, error } = await supabase.rpc("admin_update_role_droits", {
    p_role_name: roleName,
    p_droits: droits,
  });
  if (error) throw error;
  const row = (data ?? [])[0] as { id: string; name: string; droits: string[] } | undefined;
  if (!row) throw new Error("Mise à jour des droits impossible.");
  return row;
}

export function isAdminUsersRpcMissingError(message: string) {
  return (
    message.includes("list_platform_users_for_admin") ||
    message.includes("Could not find the function") ||
    message.includes("schema cache")
  );
}

export function isAdminUsersPermissionError(message: string) {
  return (
    message.includes("Droits insuffisants") ||
    message.includes("super_admin requis")
  );
}
