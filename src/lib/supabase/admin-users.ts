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

export function isAdminUsersRpcMissingError(message: string) {
  return (
    message.includes("list_platform_users_for_admin") ||
    message.includes("Could not find the function") ||
    message.includes("schema cache")
  );
}

export function isAdminUsersRpcTypeError(message: string) {
  return message.includes("structure of query does not match function result type");
}

export function isAdminUsersPermissionError(message: string) {
  return (
    message.includes("Droits insuffisants") ||
    message.includes("super_admin requis")
  );
}
