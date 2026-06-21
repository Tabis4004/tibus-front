import { supabase } from "@/lib/supabase";

export type GareTeamMember = {
  userId: string;
  firstName: string;
  lastName: string;
  email: string | null;
  roleName: string;
};

export async function listGareTeamMembersSupabase(gareId: string): Promise<GareTeamMember[]> {
  const { data, error } = await supabase.rpc("list_gare_team_members", { p_gare_id: gareId });
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => ({
    userId: String(row.user_id),
    firstName: String(row.firstName ?? ""),
    lastName: String(row.lastName ?? ""),
    email: (row.email as string | null) ?? null,
    roleName: String(row.role_name),
  }));
}

export async function assignGareTeamRoleByEmailSupabase(input: {
  gareId: string;
  email: string;
  roleName: string;
}): Promise<{ id: string; name: string; email: string | null }> {
  const { data, error } = await supabase.rpc("assign_gare_team_role_by_email", {
    p_gare_id: input.gareId,
    p_email: input.email.trim(),
    p_role_name: input.roleName,
  });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) throw new Error("Utilisateur introuvable");
  return {
    id: String(row.id),
    name: `${row.firstName ?? ""} ${row.lastName ?? ""}`.trim(),
    email: (row.email as string | null) ?? null,
  };
}

export async function removeGareTeamRoleSupabase(input: {
  gareId: string;
  userId: string;
  roleName: string;
}): Promise<void> {
  const { error } = await supabase.rpc("remove_gare_team_role", {
    p_gare_id: input.gareId,
    p_user_id: input.userId,
    p_role_name: input.roleName,
  });
  if (error) throw error;
}

export async function resolveManagedGareIdSupabase(): Promise<string | null> {
  const { data, error } = await supabase.rpc("resolve_user_managed_gare_id");
  if (error) {
    if (/resolve_user_managed_gare_id|could not find|PGRST202/i.test(error.message)) return null;
    throw error;
  }
  return data ? String(data) : null;
}
